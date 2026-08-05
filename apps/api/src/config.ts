import { z } from "zod";

const envSchema = z.object({
  NODE_ENV: z.enum(["development", "test", "production"]).default("development"),
  PORT: z.coerce.number().int().positive().default(4000),
  DATABASE_URL: z.string().min(1),
  JWT_SECRET: z.string().min(32),
  JWT_REFRESH_SECRET: z.string().min(32),
  ADMIN_EMAIL: z.string().email().default("owner@example.com"),
  ADMIN_PASSWORD: z.string().min(12).default("change-me-before-seeding"),
  APP_ORIGINS: z.string().default("http://localhost:3000"),
  API_ENABLED: z.enum(["true", "false"]).default("true"),
  SNAPSHOT_READONLY_TOKEN: z.string().min(24).optional(),
  SNAPSHOT_USER_ID: z.string().uuid().optional(),
  RATE_LIMIT_MAX: z.coerce.number().int().positive().default(120),
  RATE_LIMIT_WINDOW: z.string().default("1 minute"),
  OPENAI_ENABLED: z.enum(["true", "false"]).default("false"),
  OPENAI_API_KEY: z.string().min(20).optional(),
  OPENAI_MODEL: z.string().default("gpt-5"),
  OPENAI_PROJECT_ID: z.string().trim().min(1).optional(),
  OPENAI_CAPTURE_MODEL: z.string().trim().min(1).optional(),
  OPENAI_CHAT_MODEL: z.string().trim().min(1).optional(),
  OPENAI_SUMMARY_MODEL: z.string().trim().min(1).optional(),
  OPENAI_TIMEOUT_MS: z.coerce.number().int().positive().max(120000).default(30000),
  OPENAI_MAX_OUTPUT_TOKENS: z.coerce.number().int().positive().max(4000).default(700),
  OPENAI_DAILY_USER_BUDGET: z.coerce.number().int().positive().default(40),
  OPENAI_DAILY_TENANT_BUDGET: z.coerce.number().int().positive().default(160),
  OPENAI_GLOBAL_DAILY_BUDGET: z.coerce.number().int().positive().default(1000),
  KNOWLEDGE_MAX_DOCUMENT_BYTES: z.coerce.number().int().positive().max(1048576).default(262144),
  KNOWLEDGE_MAX_ARCHIVE_BYTES: z.coerce.number().int().positive().max(52428800).default(10485760),
  KNOWLEDGE_MAX_ARCHIVE_FILES: z.coerce.number().int().positive().max(5000).default(500),
  EMAIL_PROVIDER: z.enum(["disabled", "development", "smtp", "brevo"]).default("development"),
  EMAIL_FROM: z.string().email().default("beta@example.invalid"),
  EMAIL_FROM_NAME: z.string().trim().min(1).max(80).default("Personal Tracker Beta"),
  SMTP_HOST: z.string().min(1).optional(),
  SMTP_PORT: z.coerce.number().int().positive().max(65535).optional(),
  SMTP_USERNAME: z.string().min(1).optional(),
  SMTP_PASSWORD: z.string().min(1).optional(),
  SMTP_SECURE: z.enum(["true", "false"]).default("true"),
  BREVO_API_KEY: z.string().min(20).optional(),
  PUBLIC_APP_URL: z.string().url().default("http://localhost:3000"),
  EMAIL_VERIFICATION_URL: z.string().url().optional(),
  PASSWORD_RESET_URL: z.string().url().optional(),
  INVITATION_ACCEPT_URL: z.string().url().optional(),
  EMAIL_TOKEN_TTL_MINUTES: z.coerce.number().int().positive().max(10080).default(1440),
  RESET_RATE_LIMIT_MAX: z.coerce.number().int().positive().max(20).default(5),
  INVITATION_RESEND_RATE_LIMIT_MAX: z.coerce.number().int().positive().max(20).default(5),
  REQUIRE_EMAIL_VERIFICATION: z.enum(["true", "false"]).default("false"),
  BETA_REGISTRATION_ENABLED: z.enum(["true", "false"]).default("true"),
  BETA_INVITATIONS_ENABLED: z.enum(["true", "false"]).default("true"),
  BETA_VAULT_IMPORT_ENABLED: z.enum(["true", "false"]).default("true"),
  AI_CREDITS_ENABLED: z.enum(["true", "false"]).default("true"),
  AI_BETA_STARTER_CREDITS: z.coerce.number().int().min(0).max(100000).default(20),
  AI_CREDIT_PRICING_VERSION: z.string().trim().min(1).max(40).default("beta-2026-08"),
  AI_ALLOW_NEGATIVE_BALANCE: z.enum(["true", "false"]).default("false"),
});

export const config = envSchema.parse(process.env);
export const allowedOrigins = config.APP_ORIGINS.split(",").map((origin) => origin.trim()).filter(Boolean);

if (config.NODE_ENV === "production" && config.OPENAI_ENABLED === "true" && !config.OPENAI_API_KEY) {
  throw new Error("OPENAI_API_KEY is required when OPENAI_ENABLED=true in production");
}
if (config.NODE_ENV === "production" && config.EMAIL_PROVIDER === "development") {
  throw new Error("EMAIL_PROVIDER=development is not permitted in production");
}
if (config.NODE_ENV === "production" && config.EMAIL_PROVIDER === "smtp" && (!config.SMTP_HOST || !config.SMTP_PORT || !config.SMTP_USERNAME || !config.SMTP_PASSWORD)) {
  throw new Error("SMTP_HOST, SMTP_PORT, SMTP_USERNAME and SMTP_PASSWORD are required for production SMTP email");
}
if (config.NODE_ENV === "production" && config.EMAIL_PROVIDER === "brevo" && !config.BREVO_API_KEY) {
  throw new Error("BREVO_API_KEY is required for production Brevo email");
}
if (config.NODE_ENV === "production" && config.EMAIL_PROVIDER === "disabled" && (config.REQUIRE_EMAIL_VERIFICATION === "true" || config.BETA_INVITATIONS_ENABLED === "true")) {
  throw new Error("Production verification/invitations require a configured email provider");
}
if (config.NODE_ENV === "production" && config.REQUIRE_EMAIL_VERIFICATION !== "true") {
  throw new Error("REQUIRE_EMAIL_VERIFICATION=true is required for production beta");
}
if (config.NODE_ENV === "production" && new URL(config.PUBLIC_APP_URL).protocol !== "https:") {
  throw new Error("PUBLIC_APP_URL must use HTTPS in production");
}
if (config.NODE_ENV === "production" && config.AI_ALLOW_NEGATIVE_BALANCE !== "false") {
  throw new Error("AI_ALLOW_NEGATIVE_BALANCE must remain false in production");
}
