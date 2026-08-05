import AdmZip from "adm-zip";
import { createHash, randomUUID } from "node:crypto";
import { parse as parseYaml } from "yaml";
import type { PrismaClient } from "@prisma/client";
import type { AuthContext } from "./auth.js";
import { config } from "./config.js";
import { hashValue } from "./security.js";

type ProposedAction = "create" | "update" | "unchanged" | "conflict" | "skip";
type ManifestEntry = { path: string; title: string; documentType: string; content: string; incomingHash: string; incomingVersion: number; existingDocumentId?: string; currentVersion?: number; currentHash?: string; action: ProposedAction; errors: string[]; warning?: string; serverPreview?: string; importedPreview?: string };
type StoredManifest = { archiveHash: string; entries: ManifestEntry[]; summary: Record<string, number>; size: number };

const sha256 = (content: Buffer | string) => createHash("sha256").update(content).digest("hex");
const safePath = (value: string) => {
  const normalized = value.replaceAll("\\", "/").replace(/^\.\//, "");
  if (!normalized || normalized.startsWith("/") || /^[a-zA-Z]:/.test(normalized) || normalized.split("/").some((part) => !part || part === "." || part === "..")) throw new Error("unsafe_vault_path");
  if (normalized.startsWith(".obsidian/") || normalized.startsWith(".git/")) throw new Error("reserved_vault_path");
  if (!normalized.toLowerCase().endsWith(".md")) throw new Error("unsupported_vault_file");
  return normalized;
};
const preview = (value: string) => value.slice(0, 300);
const parseDocument = (raw: string, path: string) => {
  if (Buffer.byteLength(raw, "utf8") > config.KNOWLEDGE_MAX_DOCUMENT_BYTES) throw new Error("vault_document_too_large");
  let title = path.split("/").pop()!.replace(/\.md$/i, "");
  let documentType = "markdown";
  let version = 1;
  if (raw.startsWith("---\n")) {
    const end = raw.indexOf("\n---", 4);
    if (end < 0) throw new Error("malformed_frontmatter");
    const parsed = parseYaml(raw.slice(4, end));
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) throw new Error("malformed_frontmatter");
    const values = parsed as Record<string, unknown>;
    if (values.title != null && (typeof values.title !== "string" || !values.title.trim())) throw new Error("invalid_frontmatter_title");
    if (values.type != null && (typeof values.type !== "string" || values.type.length > 48)) throw new Error("invalid_frontmatter_type");
    if (values.version != null && (!Number.isInteger(values.version) || Number(values.version) < 1)) throw new Error("invalid_frontmatter_version");
    title = (values.title as string | undefined)?.trim() || title;
    documentType = (values.type as string | undefined)?.trim() || documentType;
    version = Number(values.version ?? 1);
  }
  return { title, documentType, version };
};
const symlink = (entry: AdmZip.IZipEntry) => (((entry.header.attr >>> 16) & 0o170000) === 0o120000);

export class VaultImportService {
  constructor(private readonly prisma: PrismaClient) {}
  async dryRun(auth: AuthContext, archive: Buffer) {
    if (archive.byteLength === 0 || archive.byteLength > config.KNOWLEDGE_MAX_ARCHIVE_BYTES) throw new Error("vault_archive_size_invalid");
    let entries: AdmZip.IZipEntry[];
    try { entries = new AdmZip(archive).getEntries(); } catch { throw new Error("invalid_vault_archive"); }
    if (entries.length > config.KNOWLEDGE_MAX_ARCHIVE_FILES) throw new Error("vault_archive_too_many_files");
    const seen = new Set<string>();
    const manifest: ManifestEntry[] = [];
    for (const entry of entries) {
      if (entry.isDirectory) continue;
      const errors: string[] = [];
      let path = entry.entryName;
      try {
        if (symlink(entry)) throw new Error("vault_symlink_rejected");
        path = safePath(path);
        if (seen.has(path.toLowerCase())) throw new Error("duplicate_vault_path");
        seen.add(path.toLowerCase());
        if (entry.header.size > config.KNOWLEDGE_MAX_DOCUMENT_BYTES) throw new Error("vault_document_too_large");
        const buffer = entry.getData();
        if (buffer.byteLength !== entry.header.size || buffer.byteLength > config.KNOWLEDGE_MAX_DOCUMENT_BYTES) throw new Error("vault_document_too_large");
        const raw = new TextDecoder("utf-8", { fatal: true }).decode(buffer);
        const parsed = parseDocument(raw, path);
        const existing = await this.prisma.knowledgeDocument.findFirst({ where: { tenantId: auth.tenantId, path }, select: { id: true, version: true, contentHash: true, content: true, updatedAt: true } });
        const incomingHash = sha256(raw);
        const action: ProposedAction = !existing ? "create" : existing.contentHash === incomingHash ? "unchanged" : parsed.version === existing.version ? "update" : "conflict";
        manifest.push({ path, title: parsed.title, documentType: parsed.documentType, content: raw, incomingHash, incomingVersion: parsed.version, existingDocumentId: existing?.id, currentVersion: existing?.version, currentHash: existing?.contentHash, action, errors, serverPreview: existing ? preview(existing.content) : undefined, importedPreview: preview(raw) });
      } catch (error) {
        errors.push(error instanceof Error ? error.message : "invalid_vault_file");
        manifest.push({ path, title: path, documentType: "unknown", content: "", incomingHash: "", incomingVersion: 0, action: "skip", errors });
      }
    }
    const summary = { totalFiles: entries.filter((entry) => !entry.isDirectory).length, validFiles: manifest.filter((entry) => entry.errors.length === 0).length, invalidFiles: manifest.filter((entry) => entry.errors.length > 0).length, newDocuments: manifest.filter((entry) => entry.action === "create").length, updatedDocuments: manifest.filter((entry) => entry.action === "update").length, unchangedDocuments: manifest.filter((entry) => entry.action === "unchanged").length, conflicts: manifest.filter((entry) => entry.action === "conflict").length, skippedFiles: manifest.filter((entry) => entry.action === "skip").length };
    const archiveHash = sha256(archive);
    const stored: StoredManifest = { archiveHash, entries: manifest, summary, size: archive.byteLength };
    const session = await this.prisma.vaultImportSession.create({ data: { tenantId: auth.tenantId, userId: auth.userId, archiveHash, manifest: stored as any, expiresAt: new Date(Date.now() + 30 * 60000) } });
    return { importSessionId: session.id, archiveHash, ...summary, warnings: manifest.flatMap((entry) => entry.warning ? [entry.warning] : []), size: archive.byteLength, expiration: session.expiresAt, files: manifest.map(({ content, ...entry }) => entry) };
  }
  async commit(auth: AuthContext, input: { importSessionId: string; archiveHash: string; idempotencyKey: string; conflicts: Record<string, "keep-server" | "import-as-conflict-copy" | "skip"> }) {
    const session = await this.prisma.vaultImportSession.findFirst({ where: { id: input.importSessionId, tenantId: auth.tenantId, userId: auth.userId } });
    if (!session || session.expiresAt <= new Date()) throw new Error("vault_import_session_expired");
    if (session.archiveHash !== input.archiveHash) throw new Error("vault_archive_hash_mismatch");
    if (session.status === "COMMITTED") {
      if (session.idempotencyKey === input.idempotencyKey) return { status: "already_committed", importSessionId: session.id };
      throw new Error("vault_import_already_committed");
    }
    const stored = session.manifest as unknown as StoredManifest;
    const result = await this.prisma.$transaction(async (db) => {
      let created = 0; let updated = 0; let copied = 0; let skipped = 0;
      for (const entry of stored.entries) {
        if (entry.errors.length || entry.action === "skip" || entry.action === "unchanged") { skipped += 1; continue; }
        const current = await db.knowledgeDocument.findFirst({ where: { tenantId: auth.tenantId, path: entry.path } });
        const changedSinceDryRun = Boolean(current && (current.version !== entry.currentVersion || current.contentHash !== entry.currentHash));
        if (entry.action === "create") {
          if (current) { skipped += 1; continue; }
          await db.knowledgeDocument.create({ data: { tenantId: auth.tenantId, path: entry.path, title: entry.title, documentType: entry.documentType, content: entry.content, contentHash: entry.incomingHash, version: entry.incomingVersion, createdByUserId: auth.userId, syncStatus: "SYNCED", lastSyncedAt: new Date() } }); created += 1; continue;
        }
        const decision = input.conflicts[entry.path];
        if (entry.action === "update" && !changedSinceDryRun) {
          await db.knowledgeDocument.update({ where: { id: current!.id }, data: { title: entry.title, documentType: entry.documentType, content: entry.content, contentHash: entry.incomingHash, version: current!.version + 1, lastSyncedAt: new Date(), syncStatus: "SYNCED" } }); updated += 1; continue;
        }
        if (decision === "import-as-conflict-copy") {
          const suffix = `-import-conflict-${randomUUID().slice(0, 8)}`;
          const path = entry.path.replace(/\.md$/i, `${suffix}.md`);
          await db.knowledgeDocument.create({ data: { tenantId: auth.tenantId, path, title: `${entry.title} (import conflict)`, documentType: entry.documentType, content: entry.content, contentHash: entry.incomingHash, version: 1, createdByUserId: auth.userId, syncStatus: "CONFLICT" } }); copied += 1;
        } else { skipped += 1; }
      }
      await db.vaultImportSession.update({ where: { id: session.id }, data: { status: "COMMITTED", committedAt: new Date(), idempotencyKey: input.idempotencyKey } });
      return { status: "committed", importSessionId: session.id, created, updated, copied, skipped };
    });
    return result;
  }
  async cleanupExpired() { return this.prisma.vaultImportSession.updateMany({ where: { status: "DRY_RUN", expiresAt: { lt: new Date() } }, data: { status: "EXPIRED" } }); }
}
