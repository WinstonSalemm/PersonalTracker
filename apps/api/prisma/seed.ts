import "dotenv/config";
import bcrypt from "bcryptjs";
import { PrismaClient } from "@prisma/client";

const prisma = new PrismaClient();
const email = (process.env.ADMIN_EMAIL ?? "owner@example.com").toLowerCase();
const password = process.env.ADMIN_PASSWORD;
if (!password || password.length < 12 || password === "replace-before-seeding") throw new Error("Set a strong ADMIN_PASSWORD before seeding.");

const user = await prisma.user.upsert({ where: { email }, update: {}, create: { email, normalizedEmail: email, displayName: email.split("@")[0], passwordHash: await bcrypt.hash(password, 12) } });
const tenant = await prisma.tenant.upsert({ where: { slug: `personal-${user.id.replaceAll("-", "")}` }, update: {}, create: { name: `${user.displayName} — personal`, slug: `personal-${user.id.replaceAll("-", "")}`, type: "PERSONAL" } });
await prisma.tenantMembership.upsert({ where: { tenantId_userId: { tenantId: tenant.id, userId: user.id } }, update: { status: "ACTIVE", role: "OWNER" }, create: { tenantId: tenant.id, userId: user.id, role: "OWNER" } });
console.log(`Seeded user ${user.id}. Put this value into SNAPSHOT_USER_ID when enabling the read-only token.`);
await prisma.$disconnect();
