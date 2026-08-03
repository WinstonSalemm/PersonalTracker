import type { PrismaClient } from "@prisma/client";
import { moneySummary, salesSummary } from "./domain.js";
import { stripSecrets } from "./security.js";

const range = (from?: string, to?: string) => ({ ...(from || to ? { date: { ...(from ? { gte: from } : {}), ...(to ? { lte: to } : {}) } } : {}) });

export async function buildAssistantSnapshot(prisma: PrismaClient, userId: string, options: { from?: string; to?: string; includeTransactions?: boolean; includeCalls?: boolean; includeEnglish?: boolean; includeSales?: boolean; mode?: "summary" | "full" }) {
  const [accounts, transactions, categories, obligations, english, leads, calls, offers, followUps, dailyGoals] = await Promise.all([
    prisma.account.findMany({ where: { userId }, orderBy: { createdAt: "asc" } }),
    prisma.transaction.findMany({ where: { userId, ...range(options.from, options.to) }, orderBy: { date: "desc" }, take: options.mode === "full" || options.includeTransactions ? 2000 : 30 }),
    prisma.category.findMany({ where: { userId } }),
    prisma.obligation.findMany({ where: { userId }, orderBy: { dueDate: "asc" } }),
    prisma.englishProgress.findMany({ where: { userId, ...range(options.from, options.to) }, orderBy: { date: "desc" }, take: 90 }),
    prisma.lead.findMany({ where: { userId }, orderBy: { createdAt: "desc" } }),
    prisma.callActivity.findMany({ where: { userId, ...(options.from || options.to ? { dateTime: { ...(options.from ? { gte: new Date(`${options.from}T00:00:00.000Z`) } : {}), ...(options.to ? { lte: new Date(`${options.to}T23:59:59.999Z`) } : {}) } } : {}) }, orderBy: { dateTime: "desc" }, take: options.mode === "full" || options.includeCalls ? 2000 : 1000 }),
    prisma.offer.findMany({ where: { userId }, orderBy: { updatedAt: "desc" } }),
    prisma.followUp.findMany({ where: { userId }, orderBy: { date: "asc" } }),
    prisma.dailyGoal.findMany({ where: { userId, ...range(options.from, options.to) }, orderBy: { date: "desc" } }),
  ]);
  const money = moneySummary(transactions.map((item) => ({ ...item, accountId: item.accountId, categoryId: item.categoryId })));
  const sales = salesSummary(calls, offers);
  const accountBalances = accounts.map((account) => { const rows = transactions.filter((item) => item.accountId === account.clientId && item.status === "completed"); const outgoing = rows.filter((item) => item.type !== "income").reduce((sum, item) => sum + item.amount, 0); const incoming = rows.filter((item) => item.type === "income").reduce((sum, item) => sum + item.amount, 0); const incomingTransfers = transactions.filter((item) => item.transferToAccountId === account.clientId && item.status === "completed").reduce((sum, item) => sum + item.amount, 0); return { accountId: account.clientId, currency: account.currency, balance: account.initialBalance + incoming - outgoing + incomingTransfers }; });
  const sourceStats = leads.reduce<Record<string, { leads: number; calls: number; won: number }>>((stats, lead) => { const row = stats[lead.source] ?? { leads: 0, calls: 0, won: 0 }; row.leads += 1; row.calls += calls.filter((call) => call.leadId === lead.clientId).length; row.won += offers.some((offer) => offer.leadId === lead.clientId && offer.status === "won") ? 1 : 0; stats[lead.source] = row; return stats; }, {});
  const categoryStats = transactions.filter((item) => item.type === "expense").reduce<Record<string, number>>((stats, item) => { const key = item.categoryId ?? "uncategorized"; stats[key] = (stats[key] ?? 0) + item.amount; return stats; }, {});
  const today = new Date().toISOString().slice(0, 10);
  const result = { version: "personal-tracker-assistant-snapshot-v1", generatedAt: new Date().toISOString(), period: { from: options.from ?? null, to: options.to ?? null }, money: { ...money, accounts: accountBalances, obligations: obligations.map((item) => ({ id: item.clientId, totalAmount: item.totalAmount, paidAmount: item.paidAmount, remaining: Math.max(0, item.totalAmount - item.paidAmount), currency: item.currency, dueDate: item.dueDate, status: item.status })) }, english: { latest: english[0] ?? null, progress: english[0]?.overallProgress ?? 0, completedDays: english[0]?.completedDays ?? 0, streak: english[0]?.streak ?? 0, studyMinutes: english[0]?.studyMinutes ?? 0 }, sales: { ...sales, leads: leads.length, followUps: { today: followUps.filter((item) => item.status !== "completed" && item.date === today).length, overdue: followUps.filter((item) => item.status !== "completed" && item.date < today).length, completed: followUps.filter((item) => item.status === "completed").length }, sourceStats, categoryStats }, dailyGoals, recentOperations: transactions.slice(0, 10), nextActions: followUps.filter((item) => item.status !== "completed").slice(0, 10) };
  const payload = { ...result, ...(options.includeTransactions || options.mode === "full" ? { transactions } : {}), ...(options.includeCalls || options.mode === "full" ? { calls } : {}), ...(options.includeEnglish || options.mode === "full" ? { englishRecords: english } : {}), ...(options.includeSales || options.mode === "full" ? { leads, offers, followUps } : {}) };
  return stripSecrets(payload, options.mode === "full");
}
