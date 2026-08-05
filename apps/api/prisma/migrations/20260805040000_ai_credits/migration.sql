CREATE TYPE "AICreditWalletStatus" AS ENUM ('ACTIVE', 'FROZEN', 'CLOSED');
CREATE TYPE "AICreditTransactionType" AS ENUM ('PURCHASE', 'BONUS', 'RESERVATION', 'CHARGE', 'RESERVATION_RELEASE', 'REFUND', 'ADJUSTMENT', 'EXPIRATION');
CREATE TYPE "AIUsageStatus" AS ENUM ('RESERVED', 'COMPLETED', 'FAILED', 'CANCELLED', 'REFUNDED');
CREATE TYPE "PaymentOrderStatus" AS ENUM ('PENDING', 'PAID', 'FAILED', 'CANCELLED', 'REFUNDED');

CREATE TABLE "AICreditWallet" (
  "id" TEXT NOT NULL,
  "tenantId" TEXT NOT NULL,
  "userId" TEXT NOT NULL,
  "balance" INTEGER NOT NULL DEFAULT 0,
  "reservedBalance" INTEGER NOT NULL DEFAULT 0,
  "lifetimePurchased" INTEGER NOT NULL DEFAULT 0,
  "lifetimeSpent" INTEGER NOT NULL DEFAULT 0,
  "currency" TEXT NOT NULL DEFAULT 'CREDITS',
  "status" "AICreditWalletStatus" NOT NULL DEFAULT 'ACTIVE',
  "version" INTEGER NOT NULL DEFAULT 1,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "AICreditWallet_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "AICreditWallet_tenantId_userId_key" ON "AICreditWallet"("tenantId", "userId");
CREATE INDEX "AICreditWallet_userId_status_idx" ON "AICreditWallet"("userId", "status");
ALTER TABLE "AICreditWallet" ADD CONSTRAINT "AICreditWallet_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "Tenant"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "AICreditWallet" ADD CONSTRAINT "AICreditWallet_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE "AICreditTransaction" (
  "id" TEXT NOT NULL, "walletId" TEXT NOT NULL, "tenantId" TEXT NOT NULL, "userId" TEXT NOT NULL,
  "type" "AICreditTransactionType" NOT NULL, "amount" INTEGER NOT NULL, "balanceBefore" INTEGER NOT NULL, "balanceAfter" INTEGER NOT NULL,
  "reason" TEXT NOT NULL, "referenceType" TEXT, "referenceId" TEXT, "idempotencyKey" TEXT NOT NULL, "metadata" JSONB, "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "AICreditTransaction_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "AICreditTransaction_idempotencyKey_key" ON "AICreditTransaction"("idempotencyKey");
CREATE INDEX "AICreditTransaction_tenantId_userId_createdAt_idx" ON "AICreditTransaction"("tenantId", "userId", "createdAt");
ALTER TABLE "AICreditTransaction" ADD CONSTRAINT "AICreditTransaction_walletId_fkey" FOREIGN KEY ("walletId") REFERENCES "AICreditWallet"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "AICreditTransaction" ADD CONSTRAINT "AICreditTransaction_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "Tenant"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "AICreditTransaction" ADD CONSTRAINT "AICreditTransaction_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE "AIUsageRecord" (
  "id" TEXT NOT NULL, "tenantId" TEXT NOT NULL, "userId" TEXT NOT NULL, "conversationId" TEXT, "requestId" TEXT NOT NULL, "requestType" TEXT NOT NULL,
  "provider" TEXT NOT NULL, "model" TEXT NOT NULL, "inputTokens" INTEGER NOT NULL DEFAULT 0, "cachedInputTokens" INTEGER NOT NULL DEFAULT 0, "outputTokens" INTEGER NOT NULL DEFAULT 0,
  "estimatedProviderCost" DECIMAL(12,6), "creditsReserved" INTEGER NOT NULL DEFAULT 0, "creditsCharged" INTEGER NOT NULL DEFAULT 0,
  "status" "AIUsageStatus" NOT NULL DEFAULT 'RESERVED', "failureReason" TEXT, "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP, "completedAt" TIMESTAMP(3),
  CONSTRAINT "AIUsageRecord_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "AIUsageRecord_tenantId_requestId_key" ON "AIUsageRecord"("tenantId", "requestId");
CREATE INDEX "AIUsageRecord_tenantId_userId_createdAt_idx" ON "AIUsageRecord"("tenantId", "userId", "createdAt");
ALTER TABLE "AIUsageRecord" ADD CONSTRAINT "AIUsageRecord_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "Tenant"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "AIUsageRecord" ADD CONSTRAINT "AIUsageRecord_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE "AICreditPackage" (
  "id" TEXT NOT NULL, "code" TEXT NOT NULL, "name" TEXT NOT NULL, "credits" INTEGER NOT NULL, "price" DECIMAL(12,2) NOT NULL, "currency" TEXT NOT NULL,
  "isActive" BOOLEAN NOT NULL DEFAULT true, "sortOrder" INTEGER NOT NULL DEFAULT 0, "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP, "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "AICreditPackage_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "AICreditPackage_code_key" ON "AICreditPackage"("code");

CREATE TABLE "PaymentOrder" (
  "id" TEXT NOT NULL, "tenantId" TEXT NOT NULL, "userId" TEXT NOT NULL, "provider" TEXT NOT NULL, "externalPaymentId" TEXT, "packageId" TEXT,
  "amount" DECIMAL(12,2) NOT NULL, "currency" TEXT NOT NULL, "credits" INTEGER NOT NULL, "status" "PaymentOrderStatus" NOT NULL DEFAULT 'PENDING',
  "idempotencyKey" TEXT NOT NULL, "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP, "paidAt" TIMESTAMP(3), "cancelledAt" TIMESTAMP(3),
  CONSTRAINT "PaymentOrder_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "PaymentOrder_idempotencyKey_key" ON "PaymentOrder"("idempotencyKey");
CREATE INDEX "PaymentOrder_tenantId_userId_status_idx" ON "PaymentOrder"("tenantId", "userId", "status");
ALTER TABLE "PaymentOrder" ADD CONSTRAINT "PaymentOrder_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "Tenant"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "PaymentOrder" ADD CONSTRAINT "PaymentOrder_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "PaymentOrder" ADD CONSTRAINT "PaymentOrder_packageId_fkey" FOREIGN KEY ("packageId") REFERENCES "AICreditPackage"("id") ON DELETE SET NULL ON UPDATE CASCADE;
