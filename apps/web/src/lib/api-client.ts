import type { EnglishState } from "@/lib/types";
import { useEnglishStore } from "@/store/use-english-store";
import { useMoneyStore } from "@/store/use-money-store";
import { useSalesStore } from "@/store/use-sales-store";

export type SnapshotMode = "summary" | "full";
export type ApiSettings = { baseUrl: string; enabled: boolean; accessToken: string; snapshotToken: string; mode: SnapshotMode; from: string; to: string };
export type SyncBatch = Record<string, unknown[]>;

const today = () => new Date().toISOString().slice(0, 10);
const progressFor = (english: EnglishState) => { const completedDays = english.days.filter((day) => day.status === "completed").length; return { id: `english-${today()}`, date: today(), overallProgress: Math.round(completedDays / Math.max(1, english.days.length) * 100), completedDays, activeDay: english.activeDayNumber, streak: english.bestStreak, studyMinutes: english.timerSessions.reduce((sum, item) => sum + item.durationSeconds, 0) / 60 }; };

export const buildSyncBatch = (): SyncBatch => {
  const english = useEnglishStore.getState(); const money = useMoneyStore.getState(); const sales = useSalesStore.getState();
  return {
    accounts: money.accounts,
    categories: money.categories,
    transactions: money.transactions,
    obligations: money.obligations,
    englishProgress: [progressFor(english)],
    leads: sales.clients,
    calls: sales.calls,
    offers: sales.opportunities.map((item) => ({ ...item, serviceName: sales.services.find((service) => service.id === item.serviceId)?.name ?? "Другое" })),
    followUps: sales.followUps,
    dailyGoals: [{ id: `sales-goal-${today()}`, date: today(), kind: "calls", target: sales.dailyCallGoal, achieved: sales.calls.filter((call) => call.dateTime.startsWith(today())).length }],
  };
};

const localSnapshot = (mode: SnapshotMode) => { const english = useEnglishStore.getState(); const money = useMoneyStore.getState(); const sales = useSalesStore.getState(); const completed = money.transactions.filter((item) => item.status === "completed"); const income = completed.filter((item) => item.type === "income").reduce((sum, item) => sum + item.amount, 0); const expense = completed.filter((item) => item.type === "expense").reduce((sum, item) => sum + item.amount, 0); const payload = { version: "personal-tracker-assistant-snapshot-local-v1", generatedAt: new Date().toISOString(), period: { from: null, to: null }, money: { income, expenses: expense, net: income - expense, accounts: money.accounts.map((account) => ({ accountId: account.id, currency: account.currency, balance: account.initialBalance })), obligations: money.obligations.map((item) => ({ totalAmount: item.totalAmount, paidAmount: item.paidAmount, remaining: Math.max(0, item.totalAmount - item.paidAmount), currency: item.currency, dueDate: item.dueDate, status: item.status })) }, english: { progress: english.days.filter((day) => day.status === "completed").length / Math.max(1, english.days.length) * 100, completedDays: english.days.filter((day) => day.status === "completed").length, streak: english.bestStreak, activeDay: english.activeDayNumber }, sales: { calls: sales.calls.length, leads: sales.clients.length, offers: sales.opportunities.length, won: sales.opportunities.filter((item) => item.status === "won").length, lost: sales.opportunities.filter((item) => item.status === "lost").length, pipeline: sales.opportunities.filter((item) => !["won", "lost"].includes(item.status)).reduce((sum, item) => sum + item.amount, 0), weightedPipeline: sales.opportunities.filter((item) => !["won", "lost"].includes(item.status)).reduce((sum, item) => sum + item.amount * item.probability / 100, 0) } }; return mode === "full" ? { ...payload, transactions: money.transactions, calls: sales.calls, leads: sales.clients, offers: sales.opportunities, followUps: sales.followUps } : payload; };

export async function apiRequest<T>(settings: ApiSettings, path: string, init: RequestInit = {}) { const response = await fetch(`${settings.baseUrl.replace(/\/$/, "")}${path}`, { ...init, headers: { "content-type": "application/json", ...(settings.accessToken ? { authorization: `Bearer ${settings.accessToken}` } : {}), ...(init.headers ?? {}) } }); if (!response.ok) throw new Error(`API ${response.status}`); return response.json() as Promise<T>; }
export async function syncToApi(settings: ApiSettings) { return apiRequest<{ accepted: number; syncedAt: string }>(settings, "/api/v1/sync/batch", { method: "POST", body: JSON.stringify(buildSyncBatch()) }); }
export async function downloadSnapshot(settings: ApiSettings, mode: SnapshotMode): Promise<Record<string, unknown>> { const params = new URLSearchParams({ mode }); if (settings.from) params.set("from", settings.from); if (settings.to) params.set("to", settings.to); const payload = settings.enabled && settings.baseUrl && (settings.accessToken || settings.snapshotToken) ? await apiRequest<Record<string, unknown>>({ ...settings, accessToken: settings.snapshotToken || settings.accessToken }, `/api/v1/export/assistant.json?${params}`) : localSnapshot(mode) as Record<string, unknown>; const blob = new Blob([JSON.stringify(payload, null, 2)], { type: "application/json" }); const url = URL.createObjectURL(blob); const link = document.createElement("a"); link.href = url; link.download = `personal-tracker-assistant-snapshot-${today()}.json`; link.click(); URL.revokeObjectURL(url); return payload;
}
