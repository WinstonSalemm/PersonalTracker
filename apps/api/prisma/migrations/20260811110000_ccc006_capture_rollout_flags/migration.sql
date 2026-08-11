CREATE TABLE "CaptureRolloutFlag" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "capability" TEXT NOT NULL,
    "enabled" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "CaptureRolloutFlag_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "CaptureRolloutFlag_userId_capability_key"
ON "CaptureRolloutFlag"("userId", "capability");

CREATE INDEX "CaptureRolloutFlag_userId_idx" ON "CaptureRolloutFlag"("userId");

ALTER TABLE "CaptureRolloutFlag"
ADD CONSTRAINT "CaptureRolloutFlag_userId_fkey"
FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
