"use client";

import { addDays, format } from "date-fns";
import { create } from "zustand";
import { createJSONStorage, persist } from "zustand/middleware";
import { buildRoadmap, START_DATE } from "@/lib/roadmap";
import type {
  EnglishState,
  MistakeItem,
  RoadmapDay,
  ExpenseItem,
  SpeakingEntry,
  TestResult,
  VocabularyItem,
  WritingEntry,
} from "@/lib/types";

const todayKey = () => format(new Date(), "yyyy-MM-dd");

const initialState: EnglishState = {
  version: 1,
  days: buildRoadmap(),
  vocabulary: [
    {
      id: "seed-vocab-1",
      expression: "follow up with the client",
      translation: "связаться с клиентом повторно",
      meaning: "to contact someone again about an earlier conversation",
      example: "I will follow up with the client tomorrow.",
      ownExample: "",
      category: "Business",
      addedAt: "2026-08-03",
      level: "B1",
      repetitions: 0,
      nextReview: "2026-08-04",
      status: "new",
    },
    {
      id: "seed-vocab-2",
      expression: "meet a deadline",
      translation: "уложиться в срок",
      meaning: "to finish something by the agreed time",
      example: "The team met the deadline despite the blocker.",
      ownExample: "",
      category: "Work",
      addedAt: "2026-08-03",
      level: "B1",
      repetitions: 0,
      nextReview: "2026-08-04",
      status: "learning",
    },
  ],
  mistakes: [
    {
      id: "seed-mistake-1",
      wrong: "He explained me the problem.",
      correct: "He explained the problem to me.",
      rule: "explain something to someone",
      ownExample: "I explained the architecture to the client.",
      category: "Prepositions",
      repetitions: 0,
      lastReviewed: "2026-08-03",
      fixed: false,
    },
  ],
  writing: [],
  speaking: [],
  tests: [],
  timerSessions: [],
  expenses: [],
  monthlyBudget: 0,
  currency: "UZS",
  activeDayNumber: 1,
  bestStreak: 0,
  lastCompletedDay: 0,
};

type EnglishActions = {
  toggleTask: (dayNumber: number, taskId: string) => void;
  updateDay: (dayNumber: number, patch: Partial<Pick<RoadmapDay, "notes" | "writtenAnswer" | "voiceLink">>) => void;
  finishDay: (dayNumber: number) => boolean;
  setActiveDay: (dayNumber: number) => void;
  addVocabulary: (item: Omit<VocabularyItem, "id" | "addedAt" | "repetitions" | "nextReview" | "status">) => void;
  reviewVocabulary: (id: string, knewIt: boolean) => void;
  addMistake: (item: Omit<MistakeItem, "id" | "repetitions" | "lastReviewed" | "fixed">) => void;
  toggleMistake: (id: string) => void;
  addWriting: (item: Omit<WritingEntry, "id" | "createdAt" | "wordCount">) => void;
  addSpeaking: (item: Omit<SpeakingEntry, "id" | "createdAt">) => void;
  saveTest: (item: Omit<TestResult, "id" | "createdAt">) => void;
  addTimerSession: (dayNumber: number, durationSeconds: number) => void;
  addExpense: (item: Omit<ExpenseItem, "id">) => void;
  deleteExpense: (id: string) => void;
  setMonthlyBudget: (amount: number) => void;
  replaceFromBackup: (state: EnglishState) => void;
  resetProgress: () => void;
};

const calculateDayStatus = (day: RoadmapDay): RoadmapDay["status"] => {
  const complete = day.tasks.filter((task) => task.required).every((task) => task.completed);
  if (complete) return "completed";
  if (day.tasks.some((task) => task.completed)) return "in_progress";
  return day.status === "locked" ? "locked" : "available";
};

export const useEnglishStore = create<EnglishState & EnglishActions>()(
  persist(
    (set, get) => ({
      ...initialState,
      toggleTask: (dayNumber, taskId) =>
        set((state) => ({
          days: state.days.map((day) => {
            if (day.dayNumber !== dayNumber || day.status === "locked") return day;
            const tasks = day.tasks.map((task) => task.id === taskId ? { ...task, completed: !task.completed } : task);
            return { ...day, tasks, status: calculateDayStatus({ ...day, tasks }) };
          }),
        })),
      updateDay: (dayNumber, patch) =>
        set((state) => ({ days: state.days.map((day) => day.dayNumber === dayNumber ? { ...day, ...patch } : day) })),
      finishDay: (dayNumber) => {
        const day = get().days.find((item) => item.dayNumber === dayNumber);
        if (!day || !day.tasks.filter((task) => task.required).every((task) => task.completed)) return false;
        set((state) => {
          const nextDay = dayNumber < 90 ? dayNumber + 1 : dayNumber;
          const streak = state.lastCompletedDay === dayNumber - 1 ? state.bestStreak + 1 : 1;
          return {
            lastCompletedDay: Math.max(state.lastCompletedDay, dayNumber),
            bestStreak: Math.max(state.bestStreak, streak),
            activeDayNumber: nextDay,
            days: state.days.map((item) => {
              if (item.dayNumber === dayNumber) return { ...item, status: "completed" as const };
              if (item.dayNumber === nextDay && item.status === "locked") return { ...item, status: "available" as const };
              return item;
            }),
          };
        });
        return true;
      },
      setActiveDay: (activeDayNumber) => set({ activeDayNumber }),
      addVocabulary: (item) => set((state) => ({
        vocabulary: [{ ...item, id: crypto.randomUUID(), addedAt: todayKey(), repetitions: 0, nextReview: format(addDays(new Date(), 1), "yyyy-MM-dd"), status: "new" as const }, ...state.vocabulary],
      })),
      reviewVocabulary: (id, knewIt) => set((state) => ({
        vocabulary: state.vocabulary.map((item) => {
          if (item.id !== id) return item;
          const repetitions = item.repetitions + 1;
          const nextInterval = knewIt ? Math.min(30, Math.max(1, 2 ** Math.min(repetitions, 5))) : 1;
          const status = knewIt ? (repetitions >= 4 ? "mastered" : repetitions >= 2 ? "familiar" : "learning") : "learning";
          return { ...item, repetitions, status, nextReview: format(addDays(new Date(), nextInterval), "yyyy-MM-dd") };
        }),
      })),
      addMistake: (item) => set((state) => ({ mistakes: [{ ...item, id: crypto.randomUUID(), repetitions: 0, lastReviewed: todayKey(), fixed: false }, ...state.mistakes] })),
      toggleMistake: (id) => set((state) => ({ mistakes: state.mistakes.map((item) => item.id === id ? { ...item, fixed: !item.fixed, repetitions: item.repetitions + 1, lastReviewed: todayKey() } : item) })),
      addWriting: (item) => set((state) => ({ writing: [{ ...item, id: crypto.randomUUID(), createdAt: todayKey(), wordCount: item.original.trim() ? item.original.trim().split(/\s+/).length : 0 }, ...state.writing] })),
      addSpeaking: (item) => set((state) => ({ speaking: [{ ...item, id: crypto.randomUUID(), createdAt: todayKey() }, ...state.speaking] })),
      saveTest: (item) => set((state) => ({ tests: [{ ...item, id: crypto.randomUUID(), createdAt: todayKey() }, ...state.tests.filter((test) => test.dayNumber !== item.dayNumber)] })),
      addTimerSession: (dayNumber, durationSeconds) => set((state) => ({ timerSessions: [{ id: crypto.randomUUID(), dayNumber, startedAt: new Date().toISOString(), durationSeconds }, ...state.timerSessions] })),
      addExpense: (item) => set((state) => ({ expenses: [{ ...item, id: crypto.randomUUID() }, ...state.expenses] })),
      deleteExpense: (id) => set((state) => ({ expenses: state.expenses.filter((item) => item.id !== id) })),
      setMonthlyBudget: (monthlyBudget) => set({ monthlyBudget: Math.max(0, monthlyBudget) }),
      replaceFromBackup: (state) => set({ ...initialState, ...state, version: 1 }),
      resetProgress: () => set({ ...initialState, days: buildRoadmap() }),
    }),
    {
      name: "english90-state",
      version: 1,
      storage: createJSONStorage(() => localStorage),
      migrate: (persisted) => {
        if (!persisted || typeof persisted !== "object") return initialState;
        return { ...initialState, ...(persisted as Partial<EnglishState>), version: 1 };
      },
      partialize: (state) => ({
        version: state.version,
        days: state.days,
        vocabulary: state.vocabulary,
        mistakes: state.mistakes,
        writing: state.writing,
        speaking: state.speaking,
        tests: state.tests,
        timerSessions: state.timerSessions,
        expenses: state.expenses,
        monthlyBudget: state.monthlyBudget,
        currency: state.currency,
        activeDayNumber: state.activeDayNumber,
        bestStreak: state.bestStreak,
        lastCompletedDay: state.lastCompletedDay,
      }),
      skipHydration: true,
    },
  ),
);

export const getTodayDayNumber = (): number => {
  const today = new Date();
  const diff = Math.floor((today.getTime() - START_DATE.getTime()) / 86_400_000) + 1;
  return Math.max(1, Math.min(90, diff));
};
