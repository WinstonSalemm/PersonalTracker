import { PrismaClient } from "@prisma/client";
import { AICreditService, InsufficientCreditsError } from "../dist/src/ai-credits.js";

const prisma = new PrismaClient();
const suffix = `${Date.now()}-${Math.random().toString(16).slice(2)}`;
const user = await prisma.user.create({ data: { email: `credit-${suffix}@example.test`, normalizedEmail: `credit-${suffix}@example.test`, passwordHash: "not-used-by-e2e", displayName: "Credit E2E" } });
const tenant = await prisma.tenant.create({ data: { name: `Credit E2E ${suffix}`, slug: `credit-e2e-${suffix}`, type: "PERSONAL" } });
await prisma.tenantMembership.create({ data: { userId: user.id, tenantId: tenant.id, role: "OWNER" } });
const context = { userId: user.id, tenantId: tenant.id };
const credits = new AICreditService(prisma);
try {
  let insufficient = false;
  try { await credits.reserve(context, "chat", `zero-${suffix}`); } catch (error) { insufficient = error instanceof InsufficientCreditsError; }
  if (!insufficient) throw new Error("zero balance did not reject before provider path");
  await credits.grant(context, 3, "E2E grant", `grant-${suffix}`, "BONUS");
  const duplicate = await credits.grant(context, 3, "E2E grant", `grant-${suffix}`, "BONUS");
  if (!duplicate.duplicate) throw new Error("duplicate grant was not idempotent");
  const results = await Promise.allSettled([
    credits.reserve(context, "chat", `parallel-a-${suffix}`),
    credits.reserve(context, "chat", `parallel-b-${suffix}`),
  ]);
  const reserved = results.filter((result) => result.status === "fulfilled").map((result) => result.value);
  if (reserved.length !== 1) throw new Error(`concurrent reservation expected one winner, got ${reserved.length}`);
  await credits.complete(context, reserved[0].id, 2, { inputTokens: 10, outputTokens: 5 });
  const balance = await credits.balance(context);
  if (balance.balance !== 1 || balance.reservedBalance !== 0) throw new Error(`ledger mismatch: ${JSON.stringify(balance)}`);
  console.log(JSON.stringify({ ok: true, zeroBalanceBlocked: true, duplicateGrant: true, concurrentReservation: true, balance: balance.balance }));
} finally {
  await prisma.$disconnect();
}
