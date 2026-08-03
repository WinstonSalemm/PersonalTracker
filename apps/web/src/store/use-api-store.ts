"use client";

import { create } from "zustand";
import { createJSONStorage, persist } from "zustand/middleware";
import type { ApiSettings, SnapshotMode } from "@/lib/api-client";

type ApiState = ApiSettings & { status: "offline" | "checking" | "online" | "error"; lastError: string; lastSyncAt: string; pendingCount: number; lastSnapshotAt: string; lastSnapshotInfo: string; setSettings: (patch: Partial<ApiSettings>) => void; setStatus: (patch: Partial<Pick<ApiState, "status" | "lastError" | "lastSyncAt" | "pendingCount" | "lastSnapshotAt" | "lastSnapshotInfo">>) => void; reset: () => void };
const initial = { baseUrl: "", enabled: false, accessToken: "", snapshotToken: "", mode: "summary" as SnapshotMode, from: "", to: "", status: "offline" as const, lastError: "", lastSyncAt: "", pendingCount: 0, lastSnapshotAt: "", lastSnapshotInfo: "" };
export const useApiStore = create<ApiState>()(persist((set) => ({ ...initial, setSettings: (patch) => set(patch), setStatus: (patch) => set(patch), reset: () => set(initial) }), { name: "english90-api-settings", storage: createJSONStorage(() => localStorage), partialize: (state) => ({ baseUrl: state.baseUrl, enabled: state.enabled, accessToken: state.accessToken, snapshotToken: state.snapshotToken, mode: state.mode, from: state.from, to: state.to, lastSyncAt: state.lastSyncAt, pendingCount: state.pendingCount, lastSnapshotAt: state.lastSnapshotAt, lastSnapshotInfo: state.lastSnapshotInfo }) }));
