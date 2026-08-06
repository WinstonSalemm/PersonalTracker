CREATE TABLE "RegistrationConsent" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "documentVersion" TEXT NOT NULL,
    "locale" TEXT NOT NULL,
    "acceptedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "RegistrationConsent_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "RegistrationConsent_userId_acceptedAt_idx" ON "RegistrationConsent"("userId", "acceptedAt");

ALTER TABLE "RegistrationConsent" ADD CONSTRAINT "RegistrationConsent_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
