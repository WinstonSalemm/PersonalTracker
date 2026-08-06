import { z } from "zod";
export const dateQuery = z.object({ from: z.string().date().optional(), to: z.string().date().optional() });
export const snapshotQuery = dateQuery.extend({ includeTransactions: z.coerce.boolean().default(false), includeCalls: z.coerce.boolean().default(false), includeEnglish: z.coerce.boolean().default(false), includeSales: z.coerce.boolean().default(false), mode: z.enum(["summary", "full"]).default("summary") });
const passwordSchema = z.string().min(12).max(128).refine((value) => /[a-zA-Z]/.test(value) && /\d/.test(value), "password must contain a letter and a number");
export const loginSchema = z.object({ email: z.string().email(), password: z.string().min(1) });
export const registerSchema = z.object({
  email: z.string().email(),
  password: passwordSchema,
  displayName: z.string().trim().min(2).max(80),
  consent: z.object({
    accepted: z.literal(true),
    documentVersion: z.string().trim().min(1).max(64),
    locale: z.string().trim().min(2).max(16),
  }),
});
export const refreshSchema = z.object({ refreshToken: z.string().min(20) });
export const tenantSwitchSchema = z.object({ tenantId: z.string().uuid() });
export const invitationAcceptSchema = z.object({ token: z.string().min(32) });
export const invitationCreateSchema = z.object({ email: z.string().email(), role: z.enum(["OWNER", "MEMBER"]).default("MEMBER"), expiresInDays: z.number().int().min(1).max(30).default(14) });
export const emailSchema = z.object({ email: z.string().email() });
export const tokenSchema = z.object({ token: z.string().min(32).max(512) });
export const resetPasswordSchema = tokenSchema.extend({ password: passwordSchema });
export const vaultImportCommitSchema = z.object({
  importSessionId: z.string().uuid(),
  archiveHash: z.string().regex(/^[a-f0-9]{64}$/),
  idempotencyKey: z.string().uuid(),
  conflicts: z.record(z.string(), z.enum(["keep-server", "import-as-conflict-copy", "skip"])).default({}),
});
export const aiCreditAdminSchema = z.object({ userId: z.string().uuid(), tenantId: z.string().uuid(), amount: z.number().int().min(1).max(100000).optional(), reason: z.string().trim().min(3).max(240), idempotencyKey: z.string().uuid() });
export const aiCreditFreezeSchema = z.object({ userId: z.string().uuid(), tenantId: z.string().uuid(), status: z.enum(["ACTIVE", "FROZEN", "CLOSED"]), reason: z.string().trim().min(3).max(240), idempotencyKey: z.string().uuid() });
export const aiCapturePreviewSchema = z.object({ text: z.string().trim().min(2).max(4000), type: z.enum(["workout", "expense", "income", "english", "sales", "note", "goal", "habit"]).optional() });
export const aiCaptureCommitSchema = z.object({ previewId: z.string().uuid(), confirmationId: z.string().uuid() });
export const aiCaptureEditSchema = z.object({ type: z.enum(["workout", "expense", "income", "english", "sales", "note", "goal", "habit"]), payload: z.record(z.string(), z.unknown()) });
export const aiChatSchema = z.object({ message: z.string().trim().min(1).max(4000), conversationId: z.string().uuid().optional() });
export const englishOnboardingSchema = z.object({
  message: z.string().trim().min(1).max(4000),
  facts: z.record(z.string(), z.string().trim().max(500)).default({}),
  history: z.array(z.object({ role: z.enum(["user", "assistant"]), content: z.string().trim().min(1).max(2000) })).max(16).default([]),
});
export const knowledgeCreateSchema = z.object({ path: z.string().min(1).max(240), title: z.string().trim().min(1).max(160), documentType: z.string().trim().min(1).max(48), content: z.string().max(262144), expectedVersion: z.number().int().positive().optional() });
export const feedbackSchema = z.object({ category: z.enum(["bug", "idea", "ux", "other"]), message: z.string().trim().min(3).max(2000), appVersion: z.string().max(64).optional(), platform: z.string().max(64).optional(), module: z.string().max(64).optional(), correlationId: z.string().max(128).optional() });
export const syncRecord = z.record(z.string(), z.unknown());
export const syncBatchSchema = z.object({ batchId: z.string().uuid().optional(), accounts: z.array(syncRecord).default([]), categories: z.array(syncRecord).default([]), transactions: z.array(syncRecord).default([]), obligations: z.array(syncRecord).default([]), englishProgress: z.array(syncRecord).default([]), leads: z.array(syncRecord).default([]), calls: z.array(syncRecord).default([]), offers: z.array(syncRecord).default([]), followUps: z.array(syncRecord).default([]), dailyGoals: z.array(syncRecord).default([]), sportMeasurements: z.array(syncRecord).default([]), workoutSessions: z.array(syncRecord).default([]), workoutExercises: z.array(syncRecord).default([]), exerciseSets: z.array(syncRecord).default([]), basketballSessions: z.array(syncRecord).default([]), recoveryCheckIns: z.array(syncRecord).default([]), sportCheckpoints: z.array(syncRecord).default([]), sportRoadmapDays: z.array(syncRecord).default([]) });
