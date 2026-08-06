import { describe, expect, it } from "vitest";

describe("registration consent contract", () => {
  it("rejects registration without explicit consent", async () => {
    const { registerSchema } = await import("../src/schemas.js");
    const result = registerSchema.safeParse({
      email: "person@example.com",
      password: "strong-password-123",
      displayName: "Person",
    });
    expect(result.success).toBe(false);
  });

  it("accepts a versioned offer and AI disclaimer consent", async () => {
    const { registerSchema } = await import("../src/schemas.js");
    const result = registerSchema.safeParse({
      email: "person@example.com",
      password: "strong-password-123",
      displayName: "Person",
      consent: { accepted: true, documentVersion: "2026-08-06-v1", locale: "ru-RU" },
    });
    expect(result.success).toBe(true);
  });
});
