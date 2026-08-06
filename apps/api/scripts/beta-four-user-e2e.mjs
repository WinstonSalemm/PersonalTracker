import { randomUUID } from "node:crypto";

const baseUrl = (process.env.E2E_API_URL || "http://127.0.0.1:4545").replace(/\/$/, "");
const password = "BetaE2ePassword123";
const suffix = randomUUID().slice(0, 8);

const call = async (path, { method = "GET", token, body, expected = 200 } = {}) => {
  const response = await fetch(`${baseUrl}${path}`, {
    method,
    headers: { ...(body == null ? {} : { "content-type": "application/json" }), ...(token ? { authorization: `Bearer ${token}` } : {}) },
    ...(body == null ? {} : { body: JSON.stringify(body) }),
  });
  const text = await response.text();
  const json = text ? JSON.parse(text) : null;
  if (response.status !== expected) throw new Error(`${method} ${path}: expected ${expected}, got ${response.status}: ${text}`);
  return json;
};

const register = async (name) => {
  const email = `${name}-${suffix}@beta.local`;
  await call("/api/auth/register", { method: "POST", expected: 201, body: { displayName: name, email, password, consent: { accepted: true, documentVersion: process.env.REGISTRATION_CONSENT_VERSION ?? "2026-08-06-v1", locale: "en-US" } } });
  return { email, ...(await call("/api/auth/login", { method: "POST", body: { email, password } })) };
};
const auth = (session) => session.accessToken;
const confirmation = () => randomUUID();

const owner = await register("owner");
const tester1 = await register("tester1");
const tester2 = await register("tester2");
const tester3 = await register("tester3");

for (const session of [owner, tester1, tester2, tester3]) {
  const me = await call("/api/auth/me", { token: auth(session) });
  const tenants = await call("/api/tenants", { token: auth(session) });
  if (me.user.email !== session.email || tenants.length !== 1 || tenants[0].tenant.id !== session.tenantId) throw new Error(`Personal tenant mismatch for ${session.email}`);
}

const invitations = [];
for (const session of [tester1, tester2, tester3]) {
  const invite = await call("/api/beta/invitations", { method: "POST", token: auth(owner), body: { email: session.email, role: "MEMBER", expiresInDays: 14 } });
  if (!invite.token) throw new Error("Local E2E must run outside production to return an invitation token");
  invitations.push(invite);
  await call("/api/invitations/accept", { method: "POST", token: auth(session), body: { token: invite.token } });
}
const listedInvitations = await call("/api/beta/invitations", { token: auth(owner) });
if (listedInvitations.filter((item) => item.status === "ACCEPTED").length < 3) throw new Error("Invitations were not accepted");

const workoutPreview = await call("/api/ai/capture/preview", { method: "POST", token: auth(tester1), body: { text: "Сегодня сделал жим лёжа 60 кг на 10, 8 и 7 повторений" } });
const workoutCommit = await call("/api/ai/capture/commit", { method: "POST", token: auth(tester1), body: { previewId: workoutPreview.id, confirmationId: confirmation() } });
if (workoutCommit.type !== "workout") throw new Error("Workout capture did not commit");
const tester1Workouts = await call("/api/v1/sport/workouts", { token: auth(tester1) });
const tester2Workouts = await call("/api/v1/sport/workouts", { token: auth(tester2) });
if (!tester1Workouts.some((workout) => workout.notes === "Жим лёжа") || tester2Workouts.some((workout) => workout.notes === "Жим лёжа")) throw new Error("Sports isolation failed");
await call(`/api/ai/capture/commit`, { method: "POST", token: auth(tester2), expected: 409, body: { previewId: workoutPreview.id, confirmationId: confirmation() } });

const expensePreview = await call("/api/ai/capture/preview", { method: "POST", token: auth(tester2), body: { text: "Купил колу за 20 тысяч сум наличными" } });
await call("/api/ai/capture/commit", { method: "POST", token: auth(tester2), body: { previewId: expensePreview.id, confirmationId: confirmation() } });
const tester1Transactions = await call("/api/v1/transactions?from=2026-01-01&to=2099-12-31", { token: auth(tester1) });
const tester2Transactions = await call("/api/v1/transactions?from=2026-01-01&to=2099-12-31", { token: auth(tester2) });
if (tester1Transactions.some((row) => row.comment?.includes("Купил колу")) || !tester2Transactions.some((row) => row.comment?.includes("Купил колу"))) throw new Error("Money isolation failed");

const knowledge = await call("/api/knowledge/documents", { method: "POST", token: auth(tester3), expected: 201, body: { path: `Daily/${suffix}.md`, title: "Private daily note", documentType: "daily-note", content: "Private tester3 content" } });
await call(`/api/knowledge/documents/${knowledge.id}`, { token: auth(owner), expected: 404 });
const vault = await call("/api/knowledge/export", { token: auth(tester3) });
if (!vault.documents.some((document) => document.id === knowledge.id)) throw new Error("Knowledge export is missing tenant document");

const chat = await call("/api/ai/chat", { method: "POST", token: auth(owner), body: { message: "Запомни: предпочитаю тренироваться утром" } });
if (!chat.memoryCandidateId) throw new Error("Memory candidate was not created");
await call(`/api/ai/memory/candidates/${chat.memoryCandidateId}/approve`, { method: "POST", token: auth(owner) });
const tester2Candidates = await call("/api/ai/memory/candidates", { token: auth(tester2) });
if (tester2Candidates.length !== 0) throw new Error("Memory isolation failed");

const rejectedSwitch = await call("/api/tenants/switch", { method: "POST", token: auth(tester2), expected: 403, body: { tenantId: tester1.tenantId } });
if (rejectedSwitch.error !== "tenant_access_denied") throw new Error("Tenant switching safeguard failed");

const refreshed = await call("/api/auth/refresh", { method: "POST", body: { refreshToken: tester3.refreshToken } });
await call("/api/auth/logout", { method: "POST", token: refreshed.accessToken, expected: 204, body: { refreshToken: refreshed.refreshToken } });
await call("/api/auth/refresh", { method: "POST", expected: 401, body: { refreshToken: refreshed.refreshToken } });

console.log(JSON.stringify({ ok: true, users: 4, invitations: 3, sportsIsolation: true, moneyIsolation: true, knowledgeIsolation: true, memoryIsolation: true, sessionLogout: true }, null, 2));
