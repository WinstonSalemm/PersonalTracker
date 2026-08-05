import { describe, expect, it } from "vitest";

process.env.DATABASE_URL = "postgresql://postgres:postgres@localhost:5432/personal_tracker?schema=public";
process.env.JWT_SECRET = "test-jwt-secret-with-at-least-32-characters-123";
process.env.JWT_REFRESH_SECRET = "test-refresh-secret-with-at-least-32-characters-123";
process.env.EMAIL_PROVIDER = "development";
process.env.PUBLIC_APP_URL = "https://beta.example.test";

describe("beta release primitives", () => {
  it("creates a high-entropy action token and stores only a non-reversible hash", async () => {
    const { authActionHash, authActionToken } = await import("../src/auth.js");
    const token = authActionToken();
    expect(token).toHaveLength(43);
    expect(authActionHash(token)).toMatch(/^[a-f0-9]{64}$/);
    expect(authActionHash(token)).not.toContain(token);
  });

  it("renders reset and invitation links with a text fallback", async () => {
    const { EmailTemplateRenderer } = await import("../src/email.js");
    const renderer = new EmailTemplateRenderer();
    const reset = renderer.passwordReset("Tester", "not-a-real-token");
    const invite = renderer.invitation("Owner", "not-a-real-token", new Date("2026-08-20T00:00:00Z"));
    expect(reset.url).toContain("token=not-a-real-token");
    expect(reset.text).toContain("not-a-real-token");
    expect(invite.text).toContain("Fallback code");
  });

  it("rejects an empty archive before any database operation", async () => {
    const { VaultImportService } = await import("../src/vault-import.js");
    const service = new VaultImportService({} as any);
    await expect(service.dryRun({ userId: "u", tenantId: "t", role: "user" }, Buffer.alloc(0))).rejects.toThrow("vault_archive_size_invalid");
  });
});
