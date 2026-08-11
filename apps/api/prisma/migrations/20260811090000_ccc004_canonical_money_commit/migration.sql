CREATE TABLE "CanonicalMoneyCommit" (
  "id" TEXT NOT NULL,
  "userId" TEXT NOT NULL,
  "captureId" TEXT NOT NULL,
  "exactMinorUnits" TEXT NOT NULL,
  "currency" TEXT NOT NULL,
  "direction" TEXT NOT NULL,
  "date" TEXT NOT NULL,
  "description" TEXT NOT NULL,
  "accountId" TEXT NOT NULL,
  "categoryId" TEXT,
  "paymentMethod" TEXT,
  "intentJson" JSONB NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "CanonicalMoneyCommit_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "CanonicalMoneyCommit_userId_captureId_key" ON "CanonicalMoneyCommit"("userId", "captureId");
CREATE INDEX "CanonicalMoneyCommit_userId_createdAt_idx" ON "CanonicalMoneyCommit"("userId", "createdAt");
ALTER TABLE "CanonicalMoneyCommit" ADD CONSTRAINT "CanonicalMoneyCommit_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
