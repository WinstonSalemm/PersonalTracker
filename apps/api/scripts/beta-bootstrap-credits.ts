import "dotenv/config";
import { PrismaClient } from "@prisma/client";
import { config } from "../src/config.js";
import { AICreditService } from "../src/ai-credits.js";

const email = process.env.BOOTSTRAP_OWNER_EMAIL?.trim().toLowerCase();
if (!email) throw new Error("BOOTSTRAP_OWNER_EMAIL is required; this command never creates a password or user.");

const prisma = new PrismaClient();
try {
  const user = await prisma.user.findUnique({ where: { normalizedEmail: email }, select: { id: true } });
  if (!user) throw new Error("Bootstrap owner is not registered. Register/verify the owner first.");
  const membership = await prisma.tenantMembership.findFirst({ where: { userId: user.id, status: "ACTIVE" }, orderBy: { createdAt: "asc" } });
  if (!membership) throw new Error("Bootstrap owner has no active tenant.");
  const credits = new AICreditService(prisma);
  const result = await credits.ensureWallet({ userId: user.id, tenantId: membership.tenantId }, true);
  await prisma.betaAuditEvent.create({ data: { tenantId: membership.tenantId, userId: user.id, eventType: "ai_credit.bootstrap", metadata: { pricingVersion: config.AI_CREDIT_PRICING_VERSION } } });
  console.log(JSON.stringify({ ok: true, walletId: result.id, balance: result.balance, pricingVersion: config.AI_CREDIT_PRICING_VERSION }));
} finally {
  await prisma.$disconnect();
}
