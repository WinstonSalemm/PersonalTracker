import { randomUUID } from "node:crypto";
import type { PrismaClient } from "@prisma/client";
import { config } from "./config.js";
import type { AuthContext } from "./auth.js";

export const aiCreditPricing = {
  version: config.AI_CREDIT_PRICING_VERSION,
  operations: {
    capture_preview: 1,
    chat: 2,
    english_onboarding: 2,
    progress_analysis: 3,
    weekly_summary: 4,
    monthly_analysis: 8,
  },
} as const;
export type AIOperation = keyof typeof aiCreditPricing.operations;
export class InsufficientCreditsError extends Error {
  constructor(readonly requiredCredits: number, readonly availableCredits: number, readonly operationType: string) { super("AI_CREDITS_INSUFFICIENT"); }
}

type CreditContext = Pick<AuthContext, "tenantId" | "userId">;
type ReservedUsage = { id: string; walletId: string; creditsReserved: number; status: string };

export class AICreditService {
  constructor(private readonly prisma: PrismaClient) {}
  async ensureWallet(context: CreditContext, starterBonus = false) {
    const existing = await this.prisma.aICreditWallet.findFirst({ where: { tenantId: context.tenantId, userId: context.userId } });
    const wallet = existing ?? await this.prisma.aICreditWallet.create({ data: { tenantId: context.tenantId, userId: context.userId } });
    if (starterBonus && config.AI_BETA_STARTER_CREDITS > 0) {
      await this.grant(context, config.AI_BETA_STARTER_CREDITS, "Beta starter credits", `starter:${config.AI_CREDIT_PRICING_VERSION}:${context.userId}`, "BONUS");
    }
    return this.prisma.aICreditWallet.findUniqueOrThrow({ where: { id: wallet.id } });
  }
  async balance(context: CreditContext) {
    const wallet = await this.ensureWallet(context);
    return { balance: wallet.balance, reservedBalance: wallet.reservedBalance, availableBalance: wallet.balance - wallet.reservedBalance, status: wallet.status, currency: wallet.currency, pricingVersion: config.AI_CREDIT_PRICING_VERSION };
  }
  async history(context: CreditContext) {
    const wallet = await this.ensureWallet(context);
    return this.prisma.aICreditTransaction.findMany({ where: { walletId: wallet.id }, select: { id: true, type: true, amount: true, balanceBefore: true, balanceAfter: true, reason: true, referenceType: true, referenceId: true, createdAt: true }, orderBy: { createdAt: "desc" }, take: 100 });
  }
  async grant(context: CreditContext, amount: number, reason: string, idempotencyKey: string, type: "BONUS" | "ADJUSTMENT" = "ADJUSTMENT") {
    if (!Number.isInteger(amount) || amount <= 0) throw new Error("invalid_credit_amount");
    return this.prisma.$transaction(async (db) => {
      const duplicate = await db.aICreditTransaction.findUnique({ where: { idempotencyKey } });
      if (duplicate) return { duplicate: true, balance: duplicate.balanceAfter };
      const wallet = await db.aICreditWallet.findFirst({ where: { tenantId: context.tenantId, userId: context.userId } }) ?? await db.aICreditWallet.create({ data: { tenantId: context.tenantId, userId: context.userId } });
      if (wallet.status !== "ACTIVE") throw new Error("ai_credit_wallet_inactive");
      const updated = await db.aICreditWallet.update({ where: { id: wallet.id }, data: { balance: { increment: amount }, lifetimePurchased: { increment: amount }, version: { increment: 1 } } });
      await db.aICreditTransaction.create({ data: { walletId: wallet.id, tenantId: context.tenantId, userId: context.userId, type, amount, balanceBefore: wallet.balance, balanceAfter: updated.balance, reason, idempotencyKey } });
      return { duplicate: false, balance: updated.balance };
    });
  }
  async freeze(context: CreditContext, status: "ACTIVE" | "FROZEN" | "CLOSED", reason: string, idempotencyKey: string) {
    return this.prisma.$transaction(async (db) => {
      const wallet = await db.aICreditWallet.findFirst({ where: { tenantId: context.tenantId, userId: context.userId } });
      if (!wallet) throw new Error("ai_credit_wallet_not_found");
      const seen = await db.aICreditTransaction.findUnique({ where: { idempotencyKey } });
      if (seen) return { duplicate: true, status: wallet.status };
      const updated = await db.aICreditWallet.update({ where: { id: wallet.id }, data: { status, version: { increment: 1 } } });
      await db.aICreditTransaction.create({ data: { walletId: wallet.id, tenantId: context.tenantId, userId: context.userId, type: "ADJUSTMENT", amount: 0, balanceBefore: wallet.balance, balanceAfter: wallet.balance, reason, idempotencyKey, metadata: { status } } });
      return { duplicate: false, status: updated.status };
    });
  }
  async reserve(context: CreditContext, operation: AIOperation, requestId: string, conversationId?: string): Promise<ReservedUsage> {
    if (config.AI_CREDITS_ENABLED !== "true") throw new Error("ai_credits_disabled");
    const amount = aiCreditPricing.operations[operation];
    return this.prisma.$transaction(async (db) => {
      const duplicate = await db.aIUsageRecord.findUnique({ where: { tenantId_requestId: { tenantId: context.tenantId, requestId } } });
      if (duplicate) return { id: duplicate.id, walletId: "", creditsReserved: duplicate.creditsReserved, status: duplicate.status };
      const wallet = await db.aICreditWallet.findFirst({ where: { tenantId: context.tenantId, userId: context.userId } }) ?? await db.aICreditWallet.create({ data: { tenantId: context.tenantId, userId: context.userId } });
      const locked = await db.$queryRaw<Array<{ balance: number; reservedBalance: number; status: string }>>`SELECT "balance", "reservedBalance", "status" FROM "AICreditWallet" WHERE "id" = ${wallet.id} FOR UPDATE`;
      const current = locked[0];
      if (!current || current.status !== "ACTIVE") throw new Error("ai_credit_wallet_inactive");
      const available = current.balance - current.reservedBalance;
      if (available < amount) throw new InsufficientCreditsError(amount, available, operation);
      await db.aICreditWallet.update({ where: { id: wallet.id }, data: { reservedBalance: { increment: amount }, version: { increment: 1 } } });
      const usage = await db.aIUsageRecord.create({ data: { tenantId: context.tenantId, userId: context.userId, conversationId, requestId, requestType: operation, provider: config.OPENAI_ENABLED === "true" ? "openai" : "local-fallback", model: config.OPENAI_MODEL, creditsReserved: amount } });
      await db.aICreditTransaction.create({ data: { walletId: wallet.id, tenantId: context.tenantId, userId: context.userId, type: "RESERVATION", amount, balanceBefore: current.balance, balanceAfter: current.balance, reason: `Reserve ${operation}`, referenceType: "AIUsageRecord", referenceId: usage.id, idempotencyKey: `reserve:${context.tenantId}:${requestId}` } });
      return { id: usage.id, walletId: wallet.id, creditsReserved: amount, status: usage.status };
    }, { isolationLevel: "Serializable" });
  }
  async complete(context: CreditContext, usageId: string, actualCredits: number, usage: { inputTokens?: number; cachedInputTokens?: number; outputTokens?: number; estimatedProviderCost?: string } = {}) {
    return this.prisma.$transaction(async (db) => {
      const record = await db.aIUsageRecord.findFirst({ where: { id: usageId, tenantId: context.tenantId, userId: context.userId } });
      if (!record) throw new Error("ai_usage_not_found");
      if (record.status === "COMPLETED") return { duplicate: true, charged: record.creditsCharged };
      if (record.status !== "RESERVED") throw new Error("ai_usage_not_reservable");
      const charge = Math.max(0, Math.min(record.creditsReserved, Math.trunc(actualCredits)));
      const wallet = await db.aICreditWallet.findUniqueOrThrow({ where: { id: (await db.aICreditTransaction.findFirst({ where: { referenceId: record.id, type: "RESERVATION" }, select: { walletId: true } }))!.walletId } });
      const locked = await db.$queryRaw<Array<{ balance: number; reservedBalance: number }>>`SELECT "balance", "reservedBalance" FROM "AICreditWallet" WHERE "id" = ${wallet.id} FOR UPDATE`;
      const current = locked[0];
      if (!current || current.reservedBalance < record.creditsReserved || current.balance < charge) throw new Error("ai_credit_ledger_inconsistent");
      const updated = await db.aICreditWallet.update({ where: { id: wallet.id }, data: { balance: { decrement: charge }, reservedBalance: { decrement: record.creditsReserved }, lifetimeSpent: { increment: charge }, version: { increment: 1 } } });
      await db.aICreditTransaction.create({ data: { walletId: wallet.id, tenantId: context.tenantId, userId: context.userId, type: "CHARGE", amount: -charge, balanceBefore: current.balance, balanceAfter: updated.balance, reason: `Charge ${record.requestType}`, referenceType: "AIUsageRecord", referenceId: record.id, idempotencyKey: `charge:${record.id}` } });
      if (record.creditsReserved > charge) await db.aICreditTransaction.create({ data: { walletId: wallet.id, tenantId: context.tenantId, userId: context.userId, type: "RESERVATION_RELEASE", amount: record.creditsReserved - charge, balanceBefore: updated.balance, balanceAfter: updated.balance, reason: `Release unused ${record.requestType} reservation`, referenceType: "AIUsageRecord", referenceId: record.id, idempotencyKey: `release:${record.id}` } });
      await db.aIUsageRecord.update({ where: { id: record.id }, data: { status: "COMPLETED", creditsCharged: charge, inputTokens: usage.inputTokens ?? 0, cachedInputTokens: usage.cachedInputTokens ?? 0, outputTokens: usage.outputTokens ?? 0, estimatedProviderCost: usage.estimatedProviderCost, completedAt: new Date() } });
      return { duplicate: false, charged: charge, balance: updated.balance };
    }, { isolationLevel: "Serializable" });
  }
  async fail(context: CreditContext, usageId: string, reason: string) {
    return this.prisma.$transaction(async (db) => {
      const record = await db.aIUsageRecord.findFirst({ where: { id: usageId, tenantId: context.tenantId, userId: context.userId } });
      if (!record || record.status !== "RESERVED") return { released: false };
      const reservation = await db.aICreditTransaction.findFirst({ where: { referenceId: record.id, type: "RESERVATION" }, select: { walletId: true } }); if (!reservation) throw new Error("ai_credit_reservation_missing");
      const wallet = await db.aICreditWallet.update({ where: { id: reservation.walletId }, data: { reservedBalance: { decrement: record.creditsReserved }, version: { increment: 1 } } });
      await db.aICreditTransaction.create({ data: { walletId: wallet.id, tenantId: context.tenantId, userId: context.userId, type: "RESERVATION_RELEASE", amount: record.creditsReserved, balanceBefore: wallet.balance, balanceAfter: wallet.balance, reason: `Release failed ${record.requestType}: ${reason.slice(0, 120)}`, referenceType: "AIUsageRecord", referenceId: record.id, idempotencyKey: `failure-release:${record.id}` } });
      await db.aIUsageRecord.update({ where: { id: record.id }, data: { status: "FAILED", failureReason: reason.slice(0, 240), completedAt: new Date() } });
      return { released: true };
    });
  }
  packages() { return this.prisma.aICreditPackage.findMany({ where: { isActive: true }, select: { code: true, name: true, credits: true, price: true, currency: true }, orderBy: { sortOrder: "asc" } }); }
}
