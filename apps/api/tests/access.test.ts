import { describe, expect, it } from "vitest";

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
});
