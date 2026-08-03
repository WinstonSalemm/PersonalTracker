import { describe, expect, it } from "vitest";
import { stripSecrets } from "../src/security.js";

describe("snapshot security", () => {
  it("removes secrets and hides PII in summary mode", () => {
    expect(stripSecrets({ password: "x", apiKey: "y", cardNumber: "1234", companyName: "Private LLC", amount: 10 })).toEqual({ amount: 10 });
  });
  it("keeps names only in explicitly requested full mode", () => {
    expect(stripSecrets({ companyName: "Private LLC", phone: "+998" }, true)).toEqual({ companyName: "Private LLC", phone: "+998" });
  });
});
