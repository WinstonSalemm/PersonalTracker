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
});

export const config = envSchema.parse(process.env);
export const allowedOrigins = config.APP_ORIGINS.split(",").map((origin) => origin.trim()).filter(Boolean);
