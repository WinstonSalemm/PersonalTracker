import bcrypt from "bcryptjs";
import { randomBytes, randomUUID } from "node:crypto";
import type { FastifyInstance, FastifyReply, FastifyRequest } from "fastify";
import type { PrismaClient } from "@prisma/client";
import { config } from "./config.js";
import { hashValue, safeEqual } from "./security.js";

export type AuthContext = { userId: string; tenantId: string; role: "user" | "assistant_snapshot" };
type AccessPayload = { userId: string; tenantId: string; role: "user" };

declare module "fastify" {
  interface FastifyRequest { auth?: AuthContext; }
  interface FastifyJWT { user: AccessPayload; }
}

const normalizeEmail = (email: string) => email.trim().toLowerCase();
const personalSlug = (userId: string) => `personal-${userId.replaceAll("-", "")}`;
const refreshHash = (token: string) => hashValue(`${config.JWT_REFRESH_SECRET}:${token}`);
export const authActionToken = () => randomBytes(32).toString("base64url");
export const authActionHash = (token: string) => hashValue(`${config.JWT_SECRET}:action:${token}`);
type RegistrationConsentInput = { documentVersion: string; locale: string };

export const createAuth = (prisma: PrismaClient) => ({
  async register(email: string, password: string, displayName: string, consent: RegistrationConsentInput) {
    const normalizedEmail = normalizeEmail(email);
    const existing = await prisma.user.findUnique({ where: { normalizedEmail } });
    if (existing) return { conflict: true as const };
    const passwordHash = await bcrypt.hash(password, 12);
    const user = await prisma.$transaction(async (db) => {
      const created = await db.user.create({ data: { email: normalizedEmail, normalizedEmail, passwordHash, displayName, status: config.REQUIRE_EMAIL_VERIFICATION === "true" ? "PENDING" : "ACTIVE" } });
      const tenant = await db.tenant.create({ data: { name: `${displayName} — personal`, slug: personalSlug(created.id), type: "PERSONAL" } });
      await db.tenantMembership.create({ data: { tenantId: tenant.id, userId: created.id, role: "OWNER", status: "ACTIVE" } });
      await db.registrationConsent.create({ data: { userId: created.id, documentVersion: consent.documentVersion, locale: consent.locale } });
      return { user: created, tenant };
    });
    return { conflict: false as const, userId: user.user.id, tenantId: user.tenant.id, email: user.user.email, displayName: user.user.displayName };
  },
  async login(email: string, password: string) {
    const user = await prisma.user.findUnique({ where: { normalizedEmail: normalizeEmail(email) } });
    if (!user || user.status !== "ACTIVE" || !(await bcrypt.compare(password, user.passwordHash))) return null;
    const membership = await prisma.tenantMembership.findFirst({ where: { userId: user.id, status: "ACTIVE" }, orderBy: { createdAt: "asc" } });
    if (!membership) return null;
    const refreshToken = `${randomUUID()}${randomUUID()}`;
    await prisma.$transaction([
      prisma.refreshToken.create({ data: { userId: user.id, tokenHash: refreshHash(refreshToken), expiresAt: new Date(Date.now() + 1000 * 60 * 60 * 24 * 30) } }),
      prisma.user.update({ where: { id: user.id }, data: { lastLoginAt: new Date() } }),
    ]);
    return { userId: user.id, tenantId: membership.tenantId, refreshToken };
  },
  async refresh(refreshToken: string) {
    const row = await prisma.refreshToken.findUnique({ where: { tokenHash: refreshHash(refreshToken) } });
    if (!row || row.revokedAt || row.expiresAt < new Date()) {
      // A known revoked token is a reuse signal: revoke its user's sessions.
      if (row) await prisma.refreshToken.updateMany({ where: { userId: row.userId, revokedAt: null }, data: { revokedAt: new Date() } });
      return null;
    }
    const membership = await prisma.tenantMembership.findFirst({ where: { userId: row.userId, status: "ACTIVE" }, orderBy: { createdAt: "asc" } });
    if (!membership) return null;
    const nextRefreshToken = `${randomUUID()}${randomUUID()}`;
    await prisma.$transaction([
      prisma.refreshToken.update({ where: { id: row.id }, data: { revokedAt: new Date() } }),
      prisma.refreshToken.create({ data: { userId: row.userId, tokenHash: refreshHash(nextRefreshToken), expiresAt: new Date(Date.now() + 1000 * 60 * 60 * 24 * 30) } }),
    ]);
    return { userId: row.userId, tenantId: membership.tenantId, refreshToken: nextRefreshToken };
  },
  async logout(refreshToken: string) {
    await prisma.refreshToken.updateMany({ where: { tokenHash: refreshHash(refreshToken), revokedAt: null }, data: { revokedAt: new Date() } });
  },
  async logoutAll(userId: string) {
    await prisma.refreshToken.updateMany({ where: { userId, revokedAt: null }, data: { revokedAt: new Date() } });
  },
  async createVerification(userId: string) {
    const token = authActionToken();
    await prisma.$transaction([
      prisma.emailVerificationToken.updateMany({ where: { userId, usedAt: null }, data: { usedAt: new Date() } }),
      prisma.emailVerificationToken.create({ data: { userId, tokenHash: authActionHash(token), expiresAt: new Date(Date.now() + config.EMAIL_TOKEN_TTL_MINUTES * 60000) } }),
    ]);
    return token;
  },
  async verifyEmail(token: string) {
    const row = await prisma.emailVerificationToken.findUnique({ where: { tokenHash: authActionHash(token) } });
    if (!row || row.usedAt || row.expiresAt <= new Date()) return null;
    const user = await prisma.$transaction(async (db) => {
      await db.emailVerificationToken.update({ where: { id: row.id }, data: { usedAt: new Date() } });
      return db.user.update({ where: { id: row.userId }, data: { emailVerifiedAt: new Date(), status: "ACTIVE" } });
    });
    return user;
  },
  async createPasswordReset(normalizedEmail: string) {
    const user = await prisma.user.findUnique({ where: { normalizedEmail }, select: { id: true, email: true, displayName: true, status: true } });
    if (!user || user.status === "SUSPENDED" || user.status === "DELETED") return null;
    const token = authActionToken();
    await prisma.$transaction([
      prisma.passwordResetToken.updateMany({ where: { userId: user.id, usedAt: null }, data: { usedAt: new Date() } }),
      prisma.passwordResetToken.create({ data: { userId: user.id, tokenHash: authActionHash(token), expiresAt: new Date(Date.now() + config.EMAIL_TOKEN_TTL_MINUTES * 60000) } }),
    ]);
    return { ...user, token };
  },
  async resetPassword(token: string, password: string) {
    const row = await prisma.passwordResetToken.findUnique({ where: { tokenHash: authActionHash(token) } });
    if (!row || row.usedAt || row.expiresAt <= new Date()) return false;
    const passwordHash = await bcrypt.hash(password, 12);
    await prisma.$transaction([
      prisma.passwordResetToken.update({ where: { id: row.id }, data: { usedAt: new Date() } }),
      prisma.passwordResetToken.updateMany({ where: { userId: row.userId, usedAt: null }, data: { usedAt: new Date() } }),
      prisma.user.update({ where: { id: row.userId }, data: { passwordHash } }),
      prisma.refreshToken.updateMany({ where: { userId: row.userId, revokedAt: null }, data: { revokedAt: new Date() } }),
    ]);
    return true;
  },
  async hasMembership(userId: string, tenantId: string) {
    return Boolean(await prisma.tenantMembership.findFirst({ where: { userId, tenantId, status: "ACTIVE" }, select: { id: true } }));
  },
  normalizeEmail,
});

export const signAccessToken = (app: FastifyInstance, userId: string, tenantId: string) => app.jwt.sign({ userId, tenantId, role: "user" }, { expiresIn: "15m" });
export const verifySnapshotToken = (token: string | undefined) => Boolean(config.SNAPSHOT_READONLY_TOKEN && token && safeEqual(token, config.SNAPSHOT_READONLY_TOKEN));
export const requireUser = async (request: FastifyRequest, reply: FastifyReply) => {
  if (config.API_ENABLED === "false") return reply.code(503).send({ error: "api_disabled" });
  try {
    await request.jwtVerify();
    const payload = request.user as AccessPayload;
    if (!payload.userId || !payload.tenantId) throw new Error("missing_tenant_context");
    request.auth = payload;
  } catch {
    return reply.code(401).send({ error: "unauthorized" });
  }
};
export const requireSnapshotRead = async (request: FastifyRequest, reply: FastifyReply) => {
  if (config.API_ENABLED === "false") return reply.code(503).send({ error: "api_disabled" });
  const token = request.headers.authorization?.replace(/^Bearer\s+/i, "");
  if (verifySnapshotToken(token)) {
    request.auth = { userId: config.SNAPSHOT_USER_ID ?? "", tenantId: "", role: "assistant_snapshot" };
    return;
  }
  return requireUser(request, reply);
};
