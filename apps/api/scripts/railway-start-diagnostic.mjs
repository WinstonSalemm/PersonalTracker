import { spawn } from "node:child_process";

const npm = process.platform === "win32" ? "npm.cmd" : "npm";
const child = (command, args) => new Promise((resolve) => {
  const proc = spawn(command, args, { stdio: "inherit", env: process.env });
  proc.once("error", (error) => {
    console.error(`[railway-start] phase=${args.join(" ")} error=${error.code ?? error.message}`);
    resolve(1);
  });
  proc.once("exit", (code, signal) => resolve(typeof code === "number" ? code : 1));
});

console.log(`[railway-start] phase=migrate-start environment=${process.env.RAILWAY_ENVIRONMENT_NAME ?? "unknown"}`);
const migrationCode = await child(process.platform === "win32" ? "npx.cmd" : "npx", ["prisma", "migrate", "deploy"]);
console.log(`[railway-start] phase=migrate-exit code=${migrationCode}`);
if (migrationCode !== 0) process.exit(migrationCode);

console.log(`[railway-start] phase=app-start port=${process.env.PORT ?? "unset"}`);
const appCode = await child(npm, ["start"]);
console.log(`[railway-start] phase=app-exit code=${appCode}`);
process.exit(appCode);
