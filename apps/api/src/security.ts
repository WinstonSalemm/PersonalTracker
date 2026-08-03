import { createHash, timingSafeEqual } from "node:crypto";

export const hashValue = (value: string) => createHash("sha256").update(value).digest("hex");
export const safeEqual = (left: string, right: string) => { const a = Buffer.from(left); const b = Buffer.from(right); return a.length === b.length && timingSafeEqual(a, b); };
const secretKeys = /password|secret|token|api[-_]?key|database[-_]?url|card(number)?|login/i;
export const stripSecrets = (value: unknown, includePII = false): unknown => { if (Array.isArray(value)) return value.map((item) => stripSecrets(item, includePII)); if (!value || typeof value !== "object") return value; const result: Record<string, unknown> = {}; for (const [key, entry] of Object.entries(value)) { if (secretKeys.test(key)) continue; if (!includePII && /^(name|companyName|contactName|phone|telegram|counterparty|recipient|sender)$/i.test(key)) continue; result[key] = stripSecrets(entry, includePII); } return result; };
export const publicAuditAction = (action: string) => action.replace(/[^a-z0-9_.:-]/gi, "_").slice(0, 80);
