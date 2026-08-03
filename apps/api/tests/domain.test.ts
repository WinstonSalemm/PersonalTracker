import { describe, expect, it } from "vitest";
import { inRange, moneySummary, salesSummary } from "../src/domain.js";

describe("domain calculations", () => {
  it("calculates income, expenses and net flow", () => {
    expect(moneySummary([{ type: "income", amount: 100, status: "completed", currency: "USD", date: "2026-08-03", accountId: "a" }, { type: "expense", amount: 25, status: "completed", currency: "USD", date: "2026-08-03", accountId: "a" }, { type: "income", amount: 50, status: "expected", currency: "USD", date: "2026-08-03", accountId: "a" }])).toMatchObject({ income: 100, expenses: 25, net: 75, completedCount: 2 });
  });
  it("calculates call and weighted pipeline metrics", () => {
    expect(salesSummary([{ dateTime: "2026-08-03", result: "owner", leadId: "l1" }, { dateTime: "2026-08-03", result: "no_answer", leadId: "l2" }], [{ amount: 1000, probability: 50, currency: "USD", status: "draft" }, { amount: 300, probability: 100, currency: "USD", status: "won" }])).toMatchObject({ calls: 2, reached: 1, owners: 1, pipeline: 1000, weightedPipeline: 500, won: 1 });
  });
  it("filters dates inclusively", () => { expect(inRange("2026-08-03", "2026-08-03", "2026-08-03")).toBe(true); expect(inRange("2026-08-04", "2026-08-03", "2026-08-03")).toBe(false); });
});
