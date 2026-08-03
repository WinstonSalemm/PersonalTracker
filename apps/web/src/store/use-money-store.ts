"use client";

import { create } from "zustand";
import { createJSONStorage, persist } from "zustand/middleware";
import { defaultCategories } from "@/lib/money";
import type { MoneyAccount, MoneyCategory, MoneyObligation, MoneyState, MoneyTransaction, RecurringTransaction } from "@/lib/types";

const today = () => new Date().toISOString().slice(0, 10);
const id = () => crypto.randomUUID();

const initialState: MoneyState = {
  version: 1,
  accounts: [],
  categories: defaultCategories,
  transactions: [],
  obligations: [],
  recurringTransactions: [],
  exchangeRate: 12500,
  baseCurrency: "UZS",
};

type MoneyActions = {
  addAccount: (account: Omit<MoneyAccount, "id" | "createdAt">) => void;
  updateAccount: (id: string, patch: Partial<Omit<MoneyAccount, "id" | "createdAt">>) => void;
  deleteAccount: (id: string) => void;
  addCategory: (category: Omit<MoneyCategory, "id" | "system">) => void;
  renameCategory: (id: string, name: string) => void;
  deleteCategory: (id: string) => void;
  addTransaction: (transaction: Omit<MoneyTransaction, "id" | "createdAt">) => void;
  updateTransaction: (id: string, patch: Partial<Omit<MoneyTransaction, "id" | "createdAt">>) => void;
  deleteTransaction: (id: string) => void;
  duplicateTransaction: (id: string) => void;
  addObligation: (obligation: Omit<MoneyObligation, "id">) => void;
  updateObligation: (id: string, patch: Partial<Omit<MoneyObligation, "id">>) => void;
  deleteObligation: (id: string) => void;
  addRecurring: (item: Omit<RecurringTransaction, "id">) => void;
  toggleRecurring: (id: string) => void;
  deleteRecurring: (id: string) => void;
  setExchangeRate: (exchangeRate: number) => void;
  setBaseCurrency: (baseCurrency: MoneyState["baseCurrency"]) => void;
  replaceFromBackup: (state: Partial<MoneyState>) => void;
  resetMoney: () => void;
};

export const useMoneyStore = create<MoneyState & MoneyActions>()(persist((set) => ({
  ...initialState,
  addAccount: (account) => set((state) => ({ accounts: [...state.accounts, { ...account, id: id(), createdAt: today() }] })),
  updateAccount: (accountId, patch) => set((state) => ({ accounts: state.accounts.map((account) => account.id === accountId ? { ...account, ...patch } : account) })),
  deleteAccount: (accountId) => set((state) => ({ accounts: state.accounts.filter((account) => account.id !== accountId) })),
  addCategory: (category) => set((state) => ({ categories: [...state.categories, { ...category, id: `${category.kind}-${id()}`, system: false }] })),
  renameCategory: (categoryId, name) => set((state) => ({ categories: state.categories.map((category) => category.id === categoryId && !category.system ? { ...category, name } : category) })),
  deleteCategory: (categoryId) => set((state) => ({ categories: state.categories.filter((category) => category.id !== categoryId || category.system) })),
  addTransaction: (transaction) => set((state) => ({ transactions: [{ ...transaction, id: id(), createdAt: new Date().toISOString() }, ...state.transactions] })),
  updateTransaction: (transactionId, patch) => set((state) => ({ transactions: state.transactions.map((transaction) => transaction.id === transactionId ? { ...transaction, ...patch } : transaction) })),
  deleteTransaction: (transactionId) => set((state) => ({ transactions: state.transactions.filter((transaction) => transaction.id !== transactionId) })),
  duplicateTransaction: (transactionId) => set((state) => { const transaction = state.transactions.find((item) => item.id === transactionId); return transaction ? { transactions: [{ ...transaction, id: id(), date: today(), createdAt: new Date().toISOString() }, ...state.transactions] } : state; }),
  addObligation: (obligation) => set((state) => ({ obligations: [{ ...obligation, id: id() }, ...state.obligations] })),
  updateObligation: (obligationId, patch) => set((state) => ({ obligations: state.obligations.map((obligation) => obligation.id === obligationId ? { ...obligation, ...patch } : obligation) })),
  deleteObligation: (obligationId) => set((state) => ({ obligations: state.obligations.filter((obligation) => obligation.id !== obligationId) })),
  addRecurring: (item) => set((state) => ({ recurringTransactions: [{ ...item, id: id() }, ...state.recurringTransactions] })),
  toggleRecurring: (itemId) => set((state) => ({ recurringTransactions: state.recurringTransactions.map((item) => item.id === itemId ? { ...item, status: item.status === "active" ? "paused" : "active" } : item) })),
  deleteRecurring: (itemId) => set((state) => ({ recurringTransactions: state.recurringTransactions.filter((item) => item.id !== itemId) })),
  setExchangeRate: (exchangeRate) => set({ exchangeRate: Math.max(0, exchangeRate) }),
  setBaseCurrency: (baseCurrency) => set({ baseCurrency }),
  replaceFromBackup: (state) => set({ ...initialState, ...state, version: 1 }),
  resetMoney: () => set({ ...initialState, categories: defaultCategories }),
}), {
  name: "english90-money",
  version: 1,
  storage: createJSONStorage(() => localStorage),
  migrate: (persisted) => ({ ...initialState, ...(persisted as Partial<MoneyState>), categories: (persisted as Partial<MoneyState>)?.categories?.length ? (persisted as Partial<MoneyState>).categories : defaultCategories, version: 1 }),
  partialize: (state) => ({ version: state.version, accounts: state.accounts, categories: state.categories, transactions: state.transactions, obligations: state.obligations, recurringTransactions: state.recurringTransactions, exchangeRate: state.exchangeRate, baseCurrency: state.baseCurrency }),
  skipHydration: true,
}));
