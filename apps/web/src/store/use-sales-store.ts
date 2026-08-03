"use client";

import { create } from "zustand";
import { createJSONStorage, persist } from "zustand/middleware";
import type { SalesCall, SalesClient, SalesFollowUp, SalesOpportunity, SalesService, SalesState } from "@/lib/types";

const id = () => crypto.randomUUID();
const today = () => new Date().toISOString().slice(0, 10);

export const defaultSalesServices: SalesService[] = [
  "Сайт", "Сайт-каталог", "Интернет-магазин", "Telegram-интеграция", "CRM", "ERP", "Автоматизация", "Аудит сайта", "Доработка сайта", "Сопровождение", "Другое",
].map((name, index) => ({ id: `service-${index + 1}`, name, system: true }));

const initialState: SalesState = { version: 1, dailyCallGoal: 30, clients: [], calls: [], opportunities: [], services: defaultSalesServices, followUps: [] };

export type SalesActions = {
  setDailyCallGoal: (goal: number) => void;
  addClient: (client: Omit<SalesClient, "id" | "createdAt">) => string;
  updateClient: (id: string, patch: Partial<Omit<SalesClient, "id" | "createdAt">>) => void;
  deleteClient: (id: string) => void;
  addCall: (call: Omit<SalesCall, "id" | "attemptNumber">) => void;
  updateCall: (id: string, patch: Partial<Omit<SalesCall, "id" | "attemptNumber">>) => void;
  deleteCall: (id: string) => void;
  upsertOpportunity: (opportunity: Omit<SalesOpportunity, "id">) => void;
  deleteOpportunity: (id: string) => void;
  addService: (name: string) => void;
  renameService: (id: string, name: string) => void;
  deleteService: (id: string) => void;
  addFollowUp: (followUp: Omit<SalesFollowUp, "id">) => void;
  updateFollowUp: (id: string, patch: Partial<Omit<SalesFollowUp, "id">>) => void;
  deleteFollowUp: (id: string) => void;
  replaceFromBackup: (state: Partial<SalesState>) => void;
  resetSales: () => void;
};

export type SalesStore = SalesState & SalesActions;

const statusByResult: Record<SalesCall["result"], SalesClient["status"]> = { no_answer: "no_answer", busy: "no_answer", wrong_number: "irrelevant", admin: "admin", owner: "owner", call_back: "follow_up", interested: "interested", lost: "lost" };

export const useSalesStore = create<SalesState & SalesActions>()(persist((set) => ({
  ...initialState,
  setDailyCallGoal: (goal) => set({ dailyCallGoal: Math.max(1, Math.round(goal) || 30) }),
  addClient: (client) => { const clientId = id(); set((state) => ({ clients: [{ ...client, id: clientId, createdAt: new Date().toISOString() }, ...state.clients] })); return clientId; },
  updateClient: (clientId, patch) => set((state) => ({ clients: state.clients.map((client) => client.id === clientId ? { ...client, ...patch } : client) })),
  deleteClient: (clientId) => set((state) => ({ clients: state.clients.filter((client) => client.id !== clientId), calls: state.calls.filter((call) => call.clientId !== clientId), opportunities: state.opportunities.filter((item) => item.clientId !== clientId), followUps: state.followUps.filter((item) => item.clientId !== clientId) })),
  addCall: (call) => set((state) => { const attempts = state.calls.filter((item) => item.clientId === call.clientId).length + 1; return { calls: [{ ...call, id: id(), attemptNumber: attempts }, ...state.calls], clients: state.clients.map((client) => client.id === call.clientId ? { ...client, status: statusByResult[call.result] } : client) }; }),
  updateCall: (callId, patch) => set((state) => ({ calls: state.calls.map((call) => call.id === callId ? { ...call, ...patch } : call) })),
  deleteCall: (callId) => set((state) => ({ calls: state.calls.filter((call) => call.id !== callId) })),
  upsertOpportunity: (opportunity) => set((state) => { const existing = state.opportunities.find((item) => item.clientId === opportunity.clientId); const next = { ...opportunity, id: existing?.id ?? id() }; return { opportunities: [next, ...state.opportunities.filter((item) => item.clientId !== opportunity.clientId)] }; }),
  deleteOpportunity: (opportunityId) => set((state) => ({ opportunities: state.opportunities.filter((item) => item.id !== opportunityId) })),
  addService: (name) => set((state) => ({ services: [...state.services, { id: id(), name: name.trim(), system: false }] })),
  renameService: (serviceId, name) => set((state) => ({ services: state.services.map((service) => service.id === serviceId && !service.system ? { ...service, name: name.trim() } : service) })),
  deleteService: (serviceId) => set((state) => ({ services: state.services.filter((service) => service.id !== serviceId || service.system) })),
  addFollowUp: (followUp) => set((state) => ({ followUps: [{ ...followUp, id: id() }, ...state.followUps] })),
  updateFollowUp: (followUpId, patch) => set((state) => ({ followUps: state.followUps.map((item) => item.id === followUpId ? { ...item, ...patch } : item) })),
  deleteFollowUp: (followUpId) => set((state) => ({ followUps: state.followUps.filter((item) => item.id !== followUpId) })),
  replaceFromBackup: (state) => set({ ...initialState, ...state, version: 1 }),
  resetSales: () => set({ ...initialState, services: defaultSalesServices }),
}), {
  name: "english90-sales",
  version: 1,
  storage: createJSONStorage(() => localStorage),
  migrate: (persisted) => ({ ...initialState, ...(persisted as Partial<SalesState>), services: (persisted as Partial<SalesState>)?.services?.length ? (persisted as Partial<SalesState>).services : defaultSalesServices, version: 1 }),
  partialize: (state) => ({ version: state.version, dailyCallGoal: state.dailyCallGoal, clients: state.clients, calls: state.calls, opportunities: state.opportunities, services: state.services, followUps: state.followUps }),
  skipHydration: true,
}));

export const getSalesDate = () => today();
