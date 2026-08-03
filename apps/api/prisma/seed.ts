import "dotenv/config";
import bcrypt from "bcryptjs";
import { PrismaClient } from "@prisma/client";

const prisma = new PrismaClient();
const email = (process.env.ADMIN_EMAIL ?? "owner@example.com").toLowerCase();
const password = process.env.ADMIN_PASSWORD;
if (!password || password.length < 12 || password === "replace-before-seeding") throw new Error("Set a strong ADMIN_PASSWORD before seeding.");

const user = await prisma.user.upsert({ where: { email }, update: {}, create: { email, passwordHash: await bcrypt.hash(password, 12) } });
console.log(`Seeded user ${user.id}. Put this value into SNAPSHOT_USER_ID when enabling the read-only token.`);
await prisma.$disconnect();
