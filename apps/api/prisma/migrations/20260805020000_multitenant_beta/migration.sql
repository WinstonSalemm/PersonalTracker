-- Beta identity and knowledge foundation. Existing personal data remains intact:
-- every pre-existing user receives a Personal tenant and membership below.
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE TYPE "UserStatus" AS ENUM ('PENDING', 'ACTIVE', 'SUSPENDED', 'DELETED');
CREATE TYPE "TenantType" AS ENUM ('PERSONAL', 'TEAM');
CREATE TYPE "MembershipRole" AS ENUM ('OWNER', 'MEMBER');
CREATE TYPE "MembershipStatus" AS ENUM ('ACTIVE', 'SUSPENDED');
CREATE TYPE "InvitationStatus" AS ENUM ('PENDING', 'REVOKED', 'ACCEPTED', 'EXPIRED');
CREATE TYPE "KnowledgeSyncStatus" AS ENUM ('LOCAL', 'SYNCED', 'CONFLICT', 'ERROR');
CREATE TYPE "MemoryStatus" AS ENUM ('EPHEMERAL', 'SESSION', 'CANDIDATE', 'CONFIRMED', 'SYSTEM_DERIVED', 'REJECTED');

ALTER TABLE "User" ADD COLUMN "normalizedEmail" TEXT;
ALTER TABLE "User" ADD COLUMN "displayName" TEXT;
ALTER TABLE "User" ADD COLUMN "status" "UserStatus" NOT NULL DEFAULT 'ACTIVE';
ALTER TABLE "User" ADD COLUMN "emailVerifiedAt" TIMESTAMP(3);
ALTER TABLE "User" ADD COLUMN "lastLoginAt" TIMESTAMP(3);
UPDATE "User" SET "normalizedEmail" = lower("email"), "displayName" = split_part("email", '@', 1) WHERE "normalizedEmail" IS NULL;
ALTER TABLE "User" ALTER COLUMN "normalizedEmail" SET NOT NULL;
ALTER TABLE "User" ALTER COLUMN "displayName" SET NOT NULL;
CREATE UNIQUE INDEX "User_normalizedEmail_key" ON "User"("normalizedEmail");

CREATE TABLE "Tenant" (
  "id" TEXT NOT NULL, "name" TEXT NOT NULL, "slug" TEXT NOT NULL, "type" "TenantType" NOT NULL DEFAULT 'PERSONAL',
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP, "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "Tenant_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "Tenant_slug_key" ON "Tenant"("slug");
CREATE TABLE "TenantMembership" (
  "id" TEXT NOT NULL, "tenantId" TEXT NOT NULL, "userId" TEXT NOT NULL, "role" "MembershipRole" NOT NULL DEFAULT 'MEMBER', "status" "MembershipStatus" NOT NULL DEFAULT 'ACTIVE',
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP, "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "TenantMembership_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "TenantMembership_tenantId_userId_key" ON "TenantMembership"("tenantId", "userId");
CREATE INDEX "TenantMembership_userId_status_idx" ON "TenantMembership"("userId", "status");
ALTER TABLE "TenantMembership" ADD CONSTRAINT "TenantMembership_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "Tenant"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "TenantMembership" ADD CONSTRAINT "TenantMembership_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- Deterministic UUIDs are deliberately avoided for legacy tenant rows: this is a one-time data migration.
INSERT INTO "Tenant" ("id", "name", "slug", "type", "createdAt", "updatedAt")
SELECT gen_random_uuid()::text, COALESCE("displayName", split_part("email", '@', 1)) || '''s space', 'personal-' || replace("id", '-', ''), 'PERSONAL', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP FROM "User";
INSERT INTO "TenantMembership" ("id", "tenantId", "userId", "role", "status", "createdAt", "updatedAt")
SELECT gen_random_uuid()::text, t."id", u."id", 'OWNER', 'ACTIVE', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP FROM "User" u JOIN "Tenant" t ON t."slug" = 'personal-' || replace(u."id", '-', '');

CREATE TABLE "Invitation" (
  "id" TEXT NOT NULL, "tenantId" TEXT NOT NULL, "email" TEXT NOT NULL, "normalizedEmail" TEXT NOT NULL, "role" "MembershipRole" NOT NULL DEFAULT 'MEMBER', "tokenHash" TEXT NOT NULL,
  "expiresAt" TIMESTAMP(3) NOT NULL, "acceptedAt" TIMESTAMP(3), "status" "InvitationStatus" NOT NULL DEFAULT 'PENDING', "invitedByUserId" TEXT NOT NULL, "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "Invitation_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "Invitation_tokenHash_key" ON "Invitation"("tokenHash");
CREATE INDEX "Invitation_normalizedEmail_status_expiresAt_idx" ON "Invitation"("normalizedEmail", "status", "expiresAt");
ALTER TABLE "Invitation" ADD CONSTRAINT "Invitation_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "Tenant"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "Invitation" ADD CONSTRAINT "Invitation_invitedByUserId_fkey" FOREIGN KEY ("invitedByUserId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE "KnowledgeDocument" (
  "id" TEXT NOT NULL, "tenantId" TEXT NOT NULL, "path" TEXT NOT NULL, "title" TEXT NOT NULL, "documentType" TEXT NOT NULL, "content" TEXT NOT NULL, "contentHash" TEXT NOT NULL,
  "version" INTEGER NOT NULL DEFAULT 1, "createdByUserId" TEXT NOT NULL, "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP, "updatedAt" TIMESTAMP(3) NOT NULL, "lastSyncedAt" TIMESTAMP(3), "syncStatus" "KnowledgeSyncStatus" NOT NULL DEFAULT 'LOCAL', "isArchived" BOOLEAN NOT NULL DEFAULT false,
  CONSTRAINT "KnowledgeDocument_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "KnowledgeDocument_tenantId_path_key" ON "KnowledgeDocument"("tenantId", "path");
CREATE INDEX "KnowledgeDocument_tenantId_documentType_updatedAt_idx" ON "KnowledgeDocument"("tenantId", "documentType", "updatedAt");
ALTER TABLE "KnowledgeDocument" ADD CONSTRAINT "KnowledgeDocument_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "Tenant"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "KnowledgeDocument" ADD CONSTRAINT "KnowledgeDocument_createdByUserId_fkey" FOREIGN KEY ("createdByUserId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

CREATE TABLE "AiConversation" ("id" TEXT NOT NULL, "tenantId" TEXT NOT NULL, "userId" TEXT NOT NULL, "title" TEXT, "summary" TEXT, "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP, "updatedAt" TIMESTAMP(3) NOT NULL, CONSTRAINT "AiConversation_pkey" PRIMARY KEY ("id"));
CREATE INDEX "AiConversation_tenantId_userId_updatedAt_idx" ON "AiConversation"("tenantId", "userId", "updatedAt");
ALTER TABLE "AiConversation" ADD CONSTRAINT "AiConversation_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "Tenant"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "AiConversation" ADD CONSTRAINT "AiConversation_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
CREATE TABLE "AiMessage" ("id" TEXT NOT NULL, "conversationId" TEXT NOT NULL, "role" TEXT NOT NULL, "content" TEXT NOT NULL, "toolName" TEXT, "toolCallId" TEXT, "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP, CONSTRAINT "AiMessage_pkey" PRIMARY KEY ("id"));
CREATE INDEX "AiMessage_conversationId_createdAt_idx" ON "AiMessage"("conversationId", "createdAt");
ALTER TABLE "AiMessage" ADD CONSTRAINT "AiMessage_conversationId_fkey" FOREIGN KEY ("conversationId") REFERENCES "AiConversation"("id") ON DELETE CASCADE ON UPDATE CASCADE;
CREATE TABLE "AiMemory" ("id" TEXT NOT NULL, "tenantId" TEXT NOT NULL, "createdByUserId" TEXT NOT NULL, "category" TEXT NOT NULL, "content" TEXT NOT NULL, "status" "MemoryStatus" NOT NULL DEFAULT 'CANDIDATE', "sourceConversationId" TEXT, "approvedAt" TIMESTAMP(3), "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP, "updatedAt" TIMESTAMP(3) NOT NULL, CONSTRAINT "AiMemory_pkey" PRIMARY KEY ("id"));
CREATE INDEX "AiMemory_tenantId_status_updatedAt_idx" ON "AiMemory"("tenantId", "status", "updatedAt");
ALTER TABLE "AiMemory" ADD CONSTRAINT "AiMemory_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "Tenant"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "AiMemory" ADD CONSTRAINT "AiMemory_createdByUserId_fkey" FOREIGN KEY ("createdByUserId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
CREATE TABLE "AiCapturePreview" ("id" TEXT NOT NULL, "tenantId" TEXT NOT NULL, "userId" TEXT NOT NULL, "type" TEXT NOT NULL, "payload" JSONB NOT NULL, "expiresAt" TIMESTAMP(3) NOT NULL, "committedAt" TIMESTAMP(3), "confirmationId" TEXT, "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP, CONSTRAINT "AiCapturePreview_pkey" PRIMARY KEY ("id"));
CREATE INDEX "AiCapturePreview_tenantId_userId_expiresAt_idx" ON "AiCapturePreview"("tenantId", "userId", "expiresAt");
CREATE UNIQUE INDEX "AiCapturePreview_tenantId_confirmationId_key" ON "AiCapturePreview"("tenantId", "confirmationId");
CREATE TABLE "BetaAuditEvent" ("id" TEXT NOT NULL, "tenantId" TEXT, "userId" TEXT, "eventType" TEXT NOT NULL, "entityType" TEXT, "entityId" TEXT, "success" BOOLEAN NOT NULL DEFAULT true, "durationMs" INTEGER, "correlationId" TEXT, "metadata" JSONB, "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP, CONSTRAINT "BetaAuditEvent_pkey" PRIMARY KEY ("id"));
CREATE INDEX "BetaAuditEvent_tenantId_eventType_createdAt_idx" ON "BetaAuditEvent"("tenantId", "eventType", "createdAt");
ALTER TABLE "BetaAuditEvent" ADD CONSTRAINT "BetaAuditEvent_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "Tenant"("id") ON DELETE SET NULL ON UPDATE CASCADE;
