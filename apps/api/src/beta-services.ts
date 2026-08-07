import { createHash, randomUUID } from "node:crypto";
import type { PrismaClient } from "@prisma/client";
import { config } from "./config.js";
import { findAiModel } from "./ai-models.js";

export type TenantContext = { userId: string; tenantId: string; requestId?: string };
const sha256 = (value: string) => createHash("sha256").update(value).digest("hex");
const cleanPath = (value: string) => {
  const path = value.replaceAll("\\", "/").replace(/^\/+/, "");
  if (!path.endsWith(".md") || path.includes("..") || path.includes("//") || path.split("/").some((segment) => !segment || !/^[\w .()-]+$/u.test(segment))) throw new Error("invalid_knowledge_path");
  return path;
};
const frontmatter = (id: string, tenantId: string, type: string, createdAt: Date, updatedAt: Date) => ["---", `id: ${id}`, `tenant_id: ${tenantId}`, `type: ${type}`, `created_at: ${createdAt.toISOString()}`, `updated_at: ${updatedAt.toISOString()}`, "source: personal-tracker", "schema_version: 1", "---", ""].join("\n");
const moneyAmount = (text: string) => {
  const match = text.match(/(\d+(?:[.,]\d+)?)\s*(тыс(?:яч[аи])?|k)?\s*(?:сум|uzs|сумов)?/iu);
  if (!match) return null;
  const number = Number(match[1].replace(",", "."));
  return match[2] ? Math.round(number * 1000) : number;
};

export const parseCapture = (text: string, requestedType?: string) => {
  const lower = text.toLowerCase();
  if (requestedType === "workout" || /(жим|тяга|присед|тренир|подход|кг)/u.test(lower)) {
    const exercise = /(жим.*(?:леж|лёжа)|bench)/u.test(lower) ? "Жим лёжа" : "Тренировка";
    const weightMatch = text.match(/(\d+(?:[.,]\d+)?)\s*кг.*?(?:на|:)?\s*(\d+(?:\s*[,/и]\s*\d+){0,8})/iu);
    const repetitions = weightMatch?.[2].match(/\d+/g)?.map(Number) ?? [];
    return {
      type: "workout",
      data: {
        title: exercise,
        date: new Date().toISOString().slice(0, 10),
        exercises: repetitions.length ? [{ name: exercise, weightKg: Number(weightMatch?.[1].replace(",", ".")), repetitions }] : [],
      },
      unresolvedFields: repetitions.length ? [] : ["sets"],
    };
  }
  const amount = moneyAmount(text);
  if (requestedType === "expense" || requestedType === "income" || (amount != null && /(купил|купила|потрат|заплат|получил|доход)/u.test(lower))) {
    const income = requestedType === "income" || /(получил|доход|заработ)/u.test(lower);
    return { type: income ? "income" : "expense", data: { amount, currency: "UZS", paymentMethod: /налич/u.test(lower) ? "cash" : null, note: text }, unresolvedFields: amount == null ? ["amount"] : [] };
  }
  if (requestedType === "sales" || /(клиент|лид|позвон)/u.test(lower)) return { type: "sales", data: { note: text }, unresolvedFields: [] };
  if (requestedType === "english" || /(english|англий|слова|урок)/u.test(lower)) return { type: "english", data: { note: text }, unresolvedFields: [] };
  return { type: "note", data: { note: text }, unresolvedFields: [] };
};

export class KnowledgeService {
  constructor(private readonly prisma: PrismaClient) {}
  async list(context: TenantContext, query?: string) {
    return this.prisma.knowledgeDocument.findMany({
      where: { tenantId: context.tenantId, isArchived: false, ...(query ? { OR: [{ title: { contains: query, mode: "insensitive" } }, { content: { contains: query, mode: "insensitive" } }] } : {}) },
      select: { id: true, path: true, title: true, documentType: true, version: true, updatedAt: true, syncStatus: true }, orderBy: { updatedAt: "desc" }, take: 100,
    });
  }
  async get(context: TenantContext, id: string) {
    return this.prisma.knowledgeDocument.findFirst({ where: { id, tenantId: context.tenantId, isArchived: false } });
  }
  async save(context: TenantContext, input: { path: string; title: string; documentType: string; content: string; expectedVersion?: number }) {
    if (Buffer.byteLength(input.content, "utf8") > config.KNOWLEDGE_MAX_DOCUMENT_BYTES) throw new Error("knowledge_document_too_large");
    const path = cleanPath(input.path);
    const existing = await this.prisma.knowledgeDocument.findFirst({ where: { tenantId: context.tenantId, path } });
    if (existing && input.expectedVersion !== existing.version) return { conflict: true as const, document: existing };
    const now = new Date();
    const raw = input.content.replace(/^---[\s\S]*?---\s*/u, "").trim();
    const content = `${frontmatter(existing?.id ?? randomUUID(), context.tenantId, input.documentType, existing?.createdAt ?? now, now)}${raw}\n`;
    const document = existing
      ? await this.prisma.knowledgeDocument.update({ where: { id: existing.id }, data: { title: input.title, documentType: input.documentType, content, contentHash: sha256(content), version: { increment: 1 }, syncStatus: "LOCAL" } })
      : await this.prisma.knowledgeDocument.create({ data: { tenantId: context.tenantId, path, title: input.title, documentType: input.documentType, content, contentHash: sha256(content), createdByUserId: context.userId } });
    return { conflict: false as const, document };
  }
}

export class CaptureService {
  constructor(private readonly prisma: PrismaClient) {}
  async preview(context: TenantContext, text: string, requestedType?: string) {
    const payload = parseCapture(text, requestedType);
    return this.prisma.aiCapturePreview.create({ data: { tenantId: context.tenantId, userId: context.userId, type: payload.type, payload: payload as object, expiresAt: new Date(Date.now() + 1000 * 60 * 15) } });
  }
  async commit(context: TenantContext, previewId: string, confirmationId: string) {
    const preview = await this.prisma.aiCapturePreview.findFirst({ where: { id: previewId, tenantId: context.tenantId, userId: context.userId, committedAt: null, expiresAt: { gt: new Date() } } });
    if (!preview) throw new Error("capture_preview_not_found");
    const existing = await this.prisma.aiCapturePreview.findFirst({ where: { tenantId: context.tenantId, confirmationId } });
    if (existing?.committedAt) return { duplicate: true, type: existing.type };
    const payload = preview.payload as { data: Record<string, unknown>; unresolvedFields?: string[] };
    if (payload.unresolvedFields?.length) throw new Error("capture_unresolved_fields");
    let entityId: string | undefined;
    await this.prisma.$transaction(async (db) => {
      if (preview.type === "expense" || preview.type === "income") {
        const id = randomUUID(); entityId = id;
        await db.transaction.create({ data: { userId: context.userId, clientId: id, accountId: "ai-capture", type: preview.type, amount: Number(payload.data.amount), currency: String(payload.data.currency ?? "UZS"), date: new Date().toISOString().slice(0, 10), paymentMethod: payload.data.paymentMethod ? String(payload.data.paymentMethod) : null, comment: String(payload.data.note ?? ""), status: "completed" } });
      } else if (preview.type === "workout") {
        const id = randomUUID(); entityId = id;
        await db.workoutSession.create({ data: { userId: context.userId, clientId: id, date: String(payload.data.date), workoutType: "gym", startedAt: new Date(), completed: true, notes: String(payload.data.title ?? "AI workout") } });
        const exercises = Array.isArray(payload.data.exercises) ? payload.data.exercises as Array<{ name: string; weightKg: number; repetitions: number[] }> : [];
        for (const exercise of exercises) {
          const exerciseId = randomUUID();
          await db.workoutExercise.create({ data: { userId: context.userId, clientId: exerciseId, workoutSessionClientId: id, nameSnapshot: exercise.name, primaryMuscleSnapshot: "unknown", targetSets: exercise.repetitions.length, targetRepRange: "captured", completed: true } });
          for (const [index, repetitions] of exercise.repetitions.entries()) await db.exerciseSet.create({ data: { userId: context.userId, clientId: randomUUID(), workoutExerciseClientId: exerciseId, setNumber: index + 1, weight: exercise.weightKg, repetitions, completed: true } });
        }
      } else {
        const document = await new KnowledgeService(db as PrismaClient).save(context, { path: `AI/Capture/${new Date().toISOString().slice(0, 10)}-${preview.id}.md`, title: "Quick capture", documentType: preview.type === "note" ? "free-note" : `${preview.type}-summary`, content: String(payload.data.note ?? "") });
        entityId = document.document.id;
      }
      await db.aiCapturePreview.update({ where: { id: preview.id }, data: { committedAt: new Date(), confirmationId } });
      await db.betaAuditEvent.create({ data: { tenantId: context.tenantId, userId: context.userId, eventType: "capture.commit", entityType: preview.type, entityId, correlationId: context.requestId } });
    });
    return { duplicate: false, type: preview.type, entityId };
  }

  async edit(context: TenantContext, previewId: string, type: string, payload: Record<string, unknown>) {
    const preview = await this.prisma.aiCapturePreview.findFirst({ where: { id: previewId, tenantId: context.tenantId, userId: context.userId, committedAt: null, expiresAt: { gt: new Date() } } });
    if (!preview) throw new Error("capture_preview_not_found");
    return this.prisma.aiCapturePreview.update({ where: { id: preview.id }, data: { type, payload: { type, data: payload, unresolvedFields: [] } as any } });
  }
}

export const aiToolDefinitions = [
  { name: "get_current_profile", description: "Returns the authenticated caller profile.", parameters: { type: "object", properties: {}, additionalProperties: false } },
  { name: "get_recent_workouts", description: "Returns up to 20 recent workouts for the authenticated tenant.", parameters: { type: "object", properties: { days: { type: "integer", minimum: 1, maximum: 42 } }, additionalProperties: false } },
  { name: "search_knowledge", description: "Searches Markdown documents only in the authenticated tenant.", parameters: { type: "object", properties: { query: { type: "string", maxLength: 200 } }, required: ["query"], additionalProperties: false } },
] as const;

function responseText(response: unknown): string {
  const value = response as {
    output?: Array<{ content?: Array<{ type?: string; text?: string }> }>;
  };
  return (value.output ?? [])
      .flatMap((item) => item.content ?? [])
      .filter((item) => item.type === "output_text" && typeof item.text === "string")
      .map((item) => item.text!)
      .join("\n")
      .trim();
}

export class AiOrchestrator {
  constructor(private readonly prisma: PrismaClient) {}
  async chat(context: TenantContext, message: string, conversationId?: string, modelId?: string) {
    const model = findAiModel(modelId);
    const today = new Date().toISOString().slice(0, 10);
    const count = await this.prisma.betaAuditEvent.count({ where: { tenantId: context.tenantId, userId: context.userId, eventType: "ai.request", createdAt: { gte: new Date(`${today}T00:00:00.000Z`) } } });
    if (count >= config.OPENAI_DAILY_USER_BUDGET) throw new Error("ai_user_budget_exceeded");
    const conversation = conversationId
      ? await this.prisma.aiConversation.findFirst({ where: { id: conversationId, tenantId: context.tenantId, userId: context.userId } })
      : await this.prisma.aiConversation.create({ data: { tenantId: context.tenantId, userId: context.userId, title: message.slice(0, 80) } });
    if (!conversation) throw new Error("conversation_not_found");
    await this.prisma.aiMessage.create({ data: { conversationId: conversation.id, role: "user", content: message } });
    const workouts = await this.prisma.workoutSession.findMany({ where: { userId: context.userId }, orderBy: { date: "desc" }, take: 3, select: { date: true, notes: true, completed: true } });
    let answer = workouts.length ? `У вас ${workouts.length} последних тренировок. Последняя: ${workouts[0].date}. Я учитываю только данные вашего личного пространства.` : "В вашем личном пространстве пока нет тренировок. Можно добавить их через Quick Capture и подтвердить preview.";
    let memoryCandidateId: string | undefined;
    if (/(запомни|remember|предпочитаю)/iu.test(message)) {
      const memory = await this.prisma.aiMemory.create({ data: { tenantId: context.tenantId, createdByUserId: context.userId, category: "preference", content: message, status: "CANDIDATE", sourceConversationId: conversation.id } });
      memoryCandidateId = memory.id; answer += " Я создал кандидата памяти: он не будет считаться подтверждённым, пока вы его не одобрите.";
    }
    const modelAnswer = await this.answerWithOpenAi(conversation.id, model.id);
    if (modelAnswer) answer = modelAnswer;
    await this.prisma.aiMessage.create({ data: { conversationId: conversation.id, role: "assistant", content: answer } });
    await this.prisma.betaAuditEvent.create({ data: { tenantId: context.tenantId, userId: context.userId, eventType: "ai.request", correlationId: context.requestId, metadata: { provider: modelAnswer ? "openai" : "safe_fallback" } } });
    return { conversationId: conversation.id, answer, memoryCandidateId, provider: modelAnswer ? "openai" : "safe_fallback", model: model.id, modelLabel: model.label, creditsPerChat: model.creditsPerChat };
  }

  private async answerWithOpenAi(conversationId: string, modelId: string): Promise<string | undefined> {
    if (config.OPENAI_ENABLED !== "true" || !config.OPENAI_API_KEY) return undefined;
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), config.OPENAI_TIMEOUT_MS);
    try {
      const history = await this.prisma.aiMessage.findMany({
        where: { conversationId },
        orderBy: { createdAt: "asc" },
        take: 16,
        select: { role: true, content: true },
      });
      const response = await fetch("https://api.openai.com/v1/responses", {
        method: "POST",
        signal: controller.signal,
        headers: {
          "content-type": "application/json",
          authorization: `Bearer ${config.OPENAI_API_KEY}`,
          ...(config.OPENAI_PROJECT_ID ? { "OpenAI-Project": config.OPENAI_PROJECT_ID } : {}),
        },
        body: JSON.stringify({
          model: modelId,
          instructions: "You are a practical AI assistant in a personal tracker. Answer in Russian unless the user asks otherwise. You can help explain, plan and reflect, but never claim you completed an external action, accessed data not included in the conversation, verified a current fact, or can guarantee an outcome. Be concise and specific. User data must stay within this conversation; do not request passwords, API keys or secret information.",
          input: history.map((turn) => ({
            role: turn.role === "assistant" ? "assistant" : "user",
            content: turn.content,
          })),
          max_output_tokens: Math.min(config.OPENAI_MAX_OUTPUT_TOKENS, 700),
          store: false,
        }),
      });
      if (!response.ok) return undefined;
      return responseText(await response.json()).slice(0, 5000) || undefined;
    } catch {
      return undefined;
    } finally {
      clearTimeout(timeout);
    }
  }
  async approveMemory(context: TenantContext, id: string, approved: boolean) {
    const memory = await this.prisma.aiMemory.findFirst({ where: { id, tenantId: context.tenantId, createdByUserId: context.userId, status: "CANDIDATE" } });
    if (!memory) throw new Error("memory_candidate_not_found");
    return this.prisma.aiMemory.update({ where: { id: memory.id }, data: { status: approved ? "CONFIRMED" : "REJECTED", approvedAt: approved ? new Date() : null } });
  }
}
