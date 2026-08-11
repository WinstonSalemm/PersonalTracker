import { spawn } from "node:child_process";

console.log(`[railway-migrate] phase=start environment=${process.env.RAILWAY_ENVIRONMENT_NAME ?? "unknown"}`);
const command = process.platform === "win32" ? "npx.cmd" : "npx";
const proc = spawn(command, ["prisma", "migrate", "deploy"], { stdio: "inherit", env: process.env });
proc.once("error", (error) => {
  console.error(`[railway-migrate] phase=error code=${error.code ?? error.message}`);
  process.exit(1);
});
proc.once("exit", (code, signal) => {
  const exitCode = typeof code === "number" ? code : 1;
  console.log(`[railway-migrate] phase=exit code=${exitCode} signal=${signal ?? "none"}`);
  process.exit(exitCode);
});
