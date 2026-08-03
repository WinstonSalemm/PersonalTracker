import { z } from "zod";
export const dateQuery = z.object({ from: z.string().date().optional(), to: z.string().date().optional() });
export const snapshotQuery = dateQuery.extend({ includeTransactions: z.coerce.boolean().default(false), includeCalls: z.coerce.boolean().default(false), includeEnglish: z.coerce.boolean().default(false), includeSales: z.coerce.boolean().default(false), mode: z.enum(["summary", "full"]).default("summary") });
export const loginSchema = z.object({ email: z.string().email(), password: z.string().min(1) });
export const refreshSchema = z.object({ refreshToken: z.string().min(20) });
export const syncRecord = z.record(z.string(), z.unknown());
export const syncBatchSchema = z.object({ batchId: z.string().uuid().optional(), accounts: z.array(syncRecord).default([]), categories: z.array(syncRecord).default([]), transactions: z.array(syncRecord).default([]), obligations: z.array(syncRecord).default([]), englishProgress: z.array(syncRecord).default([]), leads: z.array(syncRecord).default([]), calls: z.array(syncRecord).default([]), offers: z.array(syncRecord).default([]), followUps: z.array(syncRecord).default([]), dailyGoals: z.array(syncRecord).default([]) });
