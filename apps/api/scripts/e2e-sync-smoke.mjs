import { randomUUID } from "node:crypto";

const baseUrl = (process.env.E2E_API_URL || "http://localhost:4000").replace(/\/$/, "");
const email = process.env.E2E_EMAIL;
const password = process.env.E2E_PASSWORD;
if (!email || !password) throw new Error("Set E2E_EMAIL and E2E_PASSWORD; no credentials are read from source files.");

const request = async (path, init = {}) => {
  const response = await fetch(`${baseUrl}${path}`, { ...init, headers: { "content-type": "application/json", ...(init.headers || {}) } });
  const text = await response.text();
  if (!response.ok) throw new Error(`${init.method || "GET"} ${path} -> ${response.status}: ${text}`);
  return text ? JSON.parse(text) : null;
};

const session = await request("/api/v1/auth/login", { method: "POST", body: JSON.stringify({ email, password }) });
const auth = { authorization: `Bearer ${session.accessToken}` };
const id = randomUUID();
const batch = (amount) => ({ transactions: [{ id, accountId: "default-cash", type: "expense", amount, currency: "UZS", date: new Date().toISOString().slice(0, 10), categoryId: "drinks", paymentMethod: "cash", purpose: "E2E smoke cola", status: "completed" }] });

const first = await request("/api/v1/sync", { method: "POST", headers: auth, body: JSON.stringify(batch(20000)) });
const retry = await request("/api/v1/sync", { method: "POST", headers: auth, body: JSON.stringify(batch(20000)) });
const conflict = await request("/api/v1/sync", { method: "POST", headers: auth, body: JSON.stringify(batch(21000)) });
const rows = await request(`/api/v1/transactions?from=2026-01-01&to=2099-12-31`, { headers: auth });
const matches = rows.filter((row) => row.clientId === id);
if (matches.length !== 1 || matches[0].amount !== 21000) throw new Error(`Expected one last-write-wins row, got ${JSON.stringify(matches)}`);
console.log(JSON.stringify({ ok: true, clientId: id, firstAccepted: first.accepted, retryAccepted: retry.accepted, conflictAccepted: conflict.accepted, matchingRows: matches.length, finalAmount: matches[0].amount }, null, 2));
