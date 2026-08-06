import { config } from "./config.js";

export type EnglishOnboardingInput = {
  message: string;
  facts: Record<string, string>;
  history: Array<{ role: "user" | "assistant"; content: string }>;
};

type EnglishOnboardingReply = {
  reply: string;
  facts: Record<string, string>;
  missing: string[];
  ready: boolean;
  inputTokens?: number;
  outputTokens?: number;
};

const factKeys = new Set([
  "purpose",
  "deadline",
  "country",
  "university",
  "exam",
  "current_level",
  "weekly_time",
  "study_format",
]);

const missingKeys = new Set([
  "purpose",
  "deadline",
  "country",
  "university",
  "exam",
  "current_level",
  "weekly_time",
  "study_format",
]);

const instructions = `You are the English-learning intake assistant in a personal tracker. Speak Russian unless the user asks otherwise.

Your task is to have a natural, supportive conversation so the person can explain why they need English. The first topic is their goal. Analyse each free-form answer and retain every stated fact: purpose, deadline, country, university, exam, current level, weekly time, and preferred format.

Critical rules:
- Never ask again for a fact already present in KNOWN FACTS or in the latest user message. If confirmation is genuinely useful, use a short confirmation such as "Правильно: у вас 8 месяцев?" and then ask at most one new, specific question.
- Do not turn this into a checkbox questionnaire. Respond to what the person actually said before moving on.
- Ask only one focused follow-up at a time, choosing the most important missing detail for the stated goal. For studying abroad, prioritise deadline, target country/university, and required exam only when not already known.
- Never claim admission, visa success, a CEFR level, fluency, exam score, availability of a course, or that you verified an external source. Explain the uncertainty when it matters.
- Do not invent universities, requirements, dates, exams, videos, links, or user facts. If external verification is needed, say what must be checked on the official university or exam website.
- When enough context exists to make a personal starting plan, set ready=true and explain the next safe step. The user may still continue the conversation.

Return ONLY a valid JSON object with exactly these fields:
{"reply":"short natural response, maximum 3 sentences","facts":{"purpose":"..."},"missing":["field"],"ready":false}
Use only the allowed fact and missing field names listed above. Include only facts you can support from the conversation; do not erase supplied known facts.`;

function textOutput(response: unknown): string {
  const value = response as { output?: Array<{ content?: Array<{ type?: string; text?: string }> }> };
  return (value.output ?? [])
      .flatMap((item) => item.content ?? [])
      .filter((item) => item.type === "output_text" && typeof item.text === "string")
      .map((item) => item.text!)
      .join("\n")
      .trim();
}

function parseJson(text: string): Record<string, unknown> {
  const value = text.replace(/^```json\s*/iu, "").replace(/\s*```$/u, "").trim();
  const parsed = JSON.parse(value);
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) throw new Error("english_ai_invalid_json");
  return parsed as Record<string, unknown>;
}

function safeFacts(value: unknown, base: Record<string, string>) {
  const next = { ...base };
  if (!value || typeof value !== "object" || Array.isArray(value)) return next;
  for (const [key, raw] of Object.entries(value as Record<string, unknown>)) {
    if (factKeys.has(key) && typeof raw === "string" && raw.trim()) next[key] = raw.trim().slice(0, 500);
  }
  return next;
}

export class EnglishOnboardingService {
  async reply(input: EnglishOnboardingInput): Promise<EnglishOnboardingReply> {
    if (config.OPENAI_ENABLED !== "true" || !config.OPENAI_API_KEY) throw new Error("english_ai_unavailable");
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), config.OPENAI_TIMEOUT_MS);
    try {
      const response = await fetch("https://api.openai.com/v1/responses", {
        method: "POST",
        signal: controller.signal,
        headers: {
          "content-type": "application/json",
          authorization: `Bearer ${config.OPENAI_API_KEY}`,
          ...(config.OPENAI_PROJECT_ID ? { "OpenAI-Project": config.OPENAI_PROJECT_ID } : {}),
        },
        body: JSON.stringify({
          model: config.OPENAI_CHAT_MODEL || config.OPENAI_MODEL,
          instructions,
          input: [
            ...input.history.slice(-16).map((turn) => ({ role: turn.role, content: turn.content })),
            { role: "developer", content: `KNOWN FACTS: ${JSON.stringify(input.facts)}` },
            { role: "user", content: input.message },
          ],
          max_output_tokens: Math.min(config.OPENAI_MAX_OUTPUT_TOKENS, 700),
          store: false,
        }),
      });
      if (!response.ok) throw new Error(`openai_${response.status}`);
      const raw = await response.json() as { usage?: { input_tokens?: number; output_tokens?: number } };
      const parsed = parseJson(textOutput(raw));
      const reply = typeof parsed.reply === "string" ? parsed.reply.trim().slice(0, 1600) : "";
      if (!reply) throw new Error("english_ai_missing_reply");
      const facts = safeFacts(parsed.facts, input.facts);
      const missing = Array.isArray(parsed.missing)
          ? parsed.missing.filter((item): item is string => typeof item === "string" && missingKeys.has(item) && !facts[item]).slice(0, 4)
          : [];
      return {
        reply,
        facts,
        missing,
        ready: parsed.ready === true,
        inputTokens: raw.usage?.input_tokens,
        outputTokens: raw.usage?.output_tokens,
      };
    } finally {
      clearTimeout(timeout);
    }
  }
}
