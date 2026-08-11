import { describe, expect, it, vi } from "vitest";

process.env.DATABASE_URL = "postgresql://postgres:postgres@localhost:5432/personal_tracker?schema=public";
process.env.JWT_SECRET = "test-jwt-secret-with-at-least-32-characters-123";
process.env.JWT_REFRESH_SECRET = "test-refresh-secret-with-at-least-32-characters-123";
process.env.SNAPSHOT_READONLY_TOKEN = "test-readonly-snapshot-token-123456";

describe("API access boundaries", () => {
  it("rejects protected requests without a token", async () => {
    const { buildApp } = await import("../src/app.js");
    const app = await buildApp({} as any);
    expect((await app.inject({ method: "GET", url: "/api/v1/transactions" })).statusCode).toBe(401);
    expect((await app.inject({ method: "POST", url: "/api/v1/sync", payload: {} })).statusCode).toBe(401);
    expect((await app.inject({ method: "POST", url: "/api/v2/capture/commits", payload: {} })).statusCode).toBe(401);
    expect((await app.inject({ method: "GET", url: "/api/v2/capture/rollout" })).statusCode).toBe(401);
    expect((await app.inject({ method: "POST", url: "/api/v2/capture/rollout/metrics", payload: {} })).statusCode).toBe(401);
    expect((await app.inject({ method: "PUT", url: "/api/v2/admin/capture/rollout", payload: {} })).statusCode).toBe(401);
    expect((await app.inject({ method: "GET", url: "/api/v2/admin/capture/rollout/observation?userId=11111111-1111-4111-8111-111111111111" })).statusCode).toBe(401);
    expect((await app.inject({ method: "GET", url: "/api/v1/assistant/snapshot" })).statusCode).toBe(401);
    await app.close();
  }, 20000);
  it("allows the configured web origin and rejects an unlisted origin", async () => {
    const { buildApp } = await import("../src/app.js");
    const app = await buildApp({} as any);
    const allowed = await app.inject({ method: "GET", url: "/health", headers: { origin: "http://localhost:3000" } });
    const rejected = await app.inject({ method: "GET", url: "/health", headers: { origin: "https://not-allowed.example" } });
    expect(allowed.headers["access-control-allow-origin"]).toBe("http://localhost:3000");
    expect(rejected.statusCode).toBe(500);
    await app.close();
  });
  it("recognizes the separate read-only token", async () => {
    const { verifySnapshotToken } = await import("../src/auth.js");
    expect(verifySnapshotToken("test-readonly-snapshot-token-123456")).toBe(true);
    expect(verifySnapshotToken("wrong-token")).toBe(false);
  });
  it("returns only the caller's rollout flags and records a redacted metric", async () => {
    const flags = vi.fn().mockResolvedValue([
      { capability: "captureMoneyV2", enabled: true },
      { capability: "unknown_future_flag", enabled: true },
    ]);
    const metric = vi.fn().mockResolvedValue({});
    const { buildApp } = await import("../src/app.js");
    const app = await buildApp({
      captureRolloutFlag: { findMany: flags },
      betaAuditEvent: { create: metric },
    } as any);
    const token = app.jwt.sign({ userId: "11111111-1111-4111-8111-111111111111", tenantId: "22222222-2222-4222-8222-222222222222", role: "user" });
    const headers = { authorization: `Bearer ${token}` };
    const rollout = await app.inject({ method: "GET", url: "/api/v2/capture/rollout", headers });
    expect(rollout.statusCode).toBe(200);
    expect(rollout.json().flags).toEqual({ captureCoreV2Shadow: false, captureMoneyV2: true });
    expect(flags).toHaveBeenCalledWith(expect.objectContaining({ where: { userId: "11111111-1111-4111-8111-111111111111" } }));

    const reported = await app.inject({ method: "POST", url: "/api/v2/capture/rollout/metrics", headers, payload: { event: "v2_money_sync_acknowledged" } });
    expect(reported.statusCode).toBe(202);
    expect(metric).toHaveBeenCalledWith({ data: expect.objectContaining({ eventType: "capture_rollout.v2_money_sync_acknowledged" }) });
    await app.close();
  });
  it("gives a beta operator only redacted rollout observation aggregates", async () => {
    const targetUserId = "33333333-3333-4333-8333-333333333333";
    const targetTenantId = "22222222-2222-4222-8222-222222222222";
    const flags = vi.fn().mockResolvedValue([
      { capability: "captureMoneyV2", enabled: true, updatedAt: new Date("2026-08-12T09:00:00.000Z") },
    ]);
    const groupBy = vi.fn().mockResolvedValue([
      {
        eventType: "capture_rollout.v2_money_sync_acknowledged",
        _count: { _all: 1 },
        _max: { createdAt: new Date("2026-08-12T09:03:00.000Z") },
      },
    ]);
    const { buildApp } = await import("../src/app.js");
    const app = await buildApp({
      user: { findUnique: vi.fn().mockResolvedValue({ normalizedEmail: "owner@example.com" }) },
      tenantMembership: { findFirst: vi.fn().mockResolvedValue({ userId: targetUserId }) },
      captureRolloutFlag: { findMany: flags },
      betaAuditEvent: { groupBy },
    } as any);
    const token = app.jwt.sign({ userId: "11111111-1111-4111-8111-111111111111", tenantId: targetTenantId, role: "user" });
    const response = await app.inject({
      method: "GET",
      url: `/api/v2/admin/capture/rollout/observation?userId=${targetUserId}`,
      headers: { authorization: `Bearer ${token}` },
    });
    expect(response.statusCode).toBe(200);
    expect(response.json()).toMatchObject({
      userId: targetUserId,
      flags: { captureCoreV2Shadow: false, captureMoneyV2: true },
      metrics: [{ event: "v2_money_sync_acknowledged", count: 1, lastAt: "2026-08-12T09:03:00.000Z" }],
    });
    expect(groupBy).toHaveBeenCalledWith(expect.objectContaining({
      where: expect.objectContaining({ userId: targetUserId, tenantId: targetTenantId }),
    }));
    await app.close();
  });
  it("rejects an unversioned or internally inconsistent canonical Money command", async () => {
    const { buildApp } = await import("../src/app.js");
    const app = await buildApp({} as any);
    const token = app.jwt.sign({ userId: "11111111-1111-4111-8111-111111111111", tenantId: "22222222-2222-4222-8222-222222222222", role: "user" });
    const headers = { authorization: `Bearer ${token}` };
    const base = {
      captureId: "capture-1",
      exactMinorUnits: "5000000",
      currency: "UZS",
      direction: "income",
      date: "2026-08-11",
      description: "salary",
      accountId: "card-main",
      categoryId: "salary",
      paymentMethod: "card",
      intent: { kind: "money.income", direction: "income", minorUnits: "5000000", currency: "UZS", account: "card-main", category: "salary", description: "salary", paymentMethod: "card", counterparty: null },
    };
    expect((await app.inject({ method: "POST", url: "/api/v2/capture/commits", headers, payload: base })).statusCode).toBe(400);
    expect((await app.inject({ method: "POST", url: "/api/v2/capture/commits", headers, payload: { ...base, schemaVersion: 2, intent: { ...base.intent, account: "other-card" } } })).statusCode).toBe(400);
    await app.close();
  });
  it("writes V2 Money, canonical evidence and SyncEvent in one command transaction", async () => {
    const transaction = { upsert: vi.fn().mockResolvedValue({}) };
    const canonicalMoneyCommit = { findUnique: vi.fn().mockResolvedValue(null), create: vi.fn().mockResolvedValue({}) };
    const syncEvent = { upsert: vi.fn().mockResolvedValue({ id: "revision-1", syncedAt: new Date("2026-08-11T12:00:00.000Z") }) };
    const db = { transaction, canonicalMoneyCommit, syncEvent };
    const prisma = {
      account: { findFirst: vi.fn().mockResolvedValue({ clientId: "card-main" }) },
      category: { findFirst: vi.fn().mockResolvedValue({ clientId: "salary" }) },
      $transaction: vi.fn(async (work: (value: typeof db) => Promise<unknown>) => work(db)),
      auditLog: { create: vi.fn().mockResolvedValue({}) },
    };
    const { buildApp } = await import("../src/app.js");
    const app = await buildApp(prisma as any);
    const token = app.jwt.sign({ userId: "11111111-1111-4111-8111-111111111111", tenantId: "22222222-2222-4222-8222-222222222222", role: "user" });
    const response = await app.inject({ method: "POST", url: "/api/v2/capture/commits", headers: { authorization: `Bearer ${token}` }, payload: {
      schemaVersion: 2, captureId: "capture-1", exactMinorUnits: "5000000", currency: "UZS", direction: "income", date: "2026-08-11", description: "salary", accountId: "card-main", categoryId: "salary", paymentMethod: "card",
      intent: { kind: "money.income", direction: "income", minorUnits: "5000000", currency: "UZS", account: "card-main", category: "salary", description: "salary", paymentMethod: "card", counterparty: null },
    } });
    expect(response.statusCode).toBe(200);
    expect(response.json()).toMatchObject({ status: "committed", captureId: "capture-1", serverRevision: "revision-1", acknowledgedAt: "2026-08-11T12:00:00.000Z" });
    expect(prisma.$transaction).toHaveBeenCalledTimes(1);
    expect(canonicalMoneyCommit.create).toHaveBeenCalledTimes(1);
    expect(syncEvent.upsert).toHaveBeenCalledWith(expect.objectContaining({ where: { userId_entity_clientId: { userId: "11111111-1111-4111-8111-111111111111", entity: "capture_v2_money", clientId: "capture-1" } } }));
    await app.close();
  });
});
