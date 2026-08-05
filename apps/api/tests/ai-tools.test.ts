import { describe, expect, it } from "vitest";
process.env.DATABASE_URL = "postgresql://postgres:postgres@localhost:5432/personal_tracker?schema=public";
process.env.JWT_SECRET = "test-jwt-secret-with-at-least-32-characters-123";
process.env.JWT_REFRESH_SECRET = "test-refresh-secret-with-at-least-32-characters-123";

const { aiToolDefinitions, KnowledgeService } = await import("../src/beta-services.js");

describe("AI beta safety boundaries", () => {
  it("exports only explicitly allow-listed tools without identity arguments", () => {
    expect(aiToolDefinitions.map((tool) => tool.name)).toEqual(["get_current_profile", "get_recent_workouts", "search_knowledge"]);
    for (const tool of aiToolDefinitions) expect(JSON.stringify(tool.parameters)).not.toMatch(/tenantId|userId|ownerId/i);
  });

  it("queries one knowledge document with tenant filtering inside the database query", async () => {
    let where: unknown;
    const prisma = { knowledgeDocument: { findFirst: async (query: { where: unknown }) => { where = query.where; return null; } } };
    await new KnowledgeService(prisma as any).get({ tenantId: "tenant-a", userId: "user-a" }, "document-b");
    expect(where).toEqual({ id: "document-b", tenantId: "tenant-a", isArchived: false });
  });
});
