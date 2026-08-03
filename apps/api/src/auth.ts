import bcrypt from "bcryptjs";
import { randomUUID } from "node:crypto";
import type { FastifyInstance, FastifyReply, FastifyRequest } from "fastify";
import type { PrismaClient } from "@prisma/client";
import { config } from "./config.js";
import { hashValue, safeEqual } from "./security.js";

declare module "fastify" { interface FastifyRequest { auth?: { userId: string; role: "user" | "assistant_snapshot" }; } interface FastifyJWT { user: { userId: string; role: "user" }; } }
export const createAuth = (prisma: PrismaClient) => ({
  async login(email: string, password: string) { const user = await prisma.user.findUnique({ where: { email: email.toLowerCase() } }); if (!user || !(await bcrypt.compare(password, user.passwordHash))) return null; const refreshToken = randomUUID() + randomUUID(); await prisma.refreshToken.create({ data: { userId: user.id, tokenHash: hashValue(`${config.JWT_REFRESH_SECRET}:${refreshToken}`), expiresAt: new Date(Date.now() + 1000 * 60 * 60 * 24 * 30) } }); return { userId: user.id, refreshToken }; },
  async refresh(refreshToken: string) { const row = await prisma.refreshToken.findUnique({ where: { tokenHash: hashValue(`${config.JWT_REFRESH_SECRET}:${refreshToken}`) } }); if (!row || row.revokedAt || row.expiresAt < new Date()) return null; return { userId: row.userId }; },
  async logout(refreshToken: string) { await prisma.refreshToken.updateMany({ where: { tokenHash: hashValue(`${config.JWT_REFRESH_SECRET}:${refreshToken}`), revokedAt: null }, data: { revokedAt: new Date() } }); },
});
export const signAccessToken = (app: FastifyInstance, userId: string) => app.jwt.sign({ userId, role: "user" }, { expiresIn: "15m" });
export const verifySnapshotToken = (token: string | undefined) => Boolean(config.SNAPSHOT_READONLY_TOKEN && token && safeEqual(token, config.SNAPSHOT_READONLY_TOKEN));
export const requireUser = async (request: FastifyRequest, reply: FastifyReply) => { if (config.API_ENABLED === "false") return reply.code(503).send({ error: "api_disabled" }); try { await request.jwtVerify(); const payload = request.user as { userId: string }; request.auth = { userId: payload.userId, role: "user" }; } catch { return reply.code(401).send({ error: "unauthorized" }); } };
export const requireSnapshotRead = async (request: FastifyRequest, reply: FastifyReply) => { if (config.API_ENABLED === "false") return reply.code(503).send({ error: "api_disabled" }); const token = request.headers.authorization?.replace(/^Bearer\s+/i, ""); if (verifySnapshotToken(token)) { request.auth = { userId: config.SNAPSHOT_USER_ID ?? "", role: "assistant_snapshot" }; return; } return requireUser(request, reply); };
