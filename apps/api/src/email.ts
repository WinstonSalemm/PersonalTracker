import { mkdir, writeFile } from "node:fs/promises";
import { join } from "node:path";
import nodemailer from "nodemailer";
import { config } from "./config.js";

export type EmailKind = "verification" | "password-reset" | "invitation";
type EmailInput = { to: string; subject: string; html: string; text: string; kind: EmailKind };
export type DeliveryResult = { status: "SENT" | "FAILED" | "DEVELOPMENT"; providerMessageId?: string };

const escapeHtml = (value: string) => value.replace(/[&<>"']/g, (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[char] ?? char);
const actionUrl = (configured: string | undefined, fallbackPath: string, token: string) => {
  const base = configured ?? new URL(fallbackPath, config.PUBLIC_APP_URL).toString();
  const url = new URL(base);
  url.searchParams.set("token", token);
  return url.toString();
};
const render = (title: string, body: string, url: string, button: string, footer: string) => ({
  html: `<main style="font-family:Arial,sans-serif;max-width:600px;margin:auto"><h1>${escapeHtml(title)}</h1><p>${escapeHtml(body)}</p><p><a href="${escapeHtml(url)}" style="display:inline-block;padding:12px 18px;background:#b8872d;color:#fff;text-decoration:none;border-radius:6px">${escapeHtml(button)}</a></p><p style="word-break:break-all">${escapeHtml(url)}</p><p>${escapeHtml(footer)}</p></main>`,
  text: `${title}\n\n${body}\n\n${button}: ${url}\n\n${footer}`,
});

export class EmailTemplateRenderer {
  verification(name: string, token: string) {
    const url = actionUrl(config.EMAIL_VERIFICATION_URL, "/verify-email", token);
    const message = render("Confirm your email", `Hi ${name}, confirm this email address to activate Personal Tracker Beta. This link expires in ${config.EMAIL_TOKEN_TTL_MINUTES} minutes.`, url, "Confirm email", "If you did not create this account, ignore this email.");
    return {
      html: message.html.replace("</main>", `<p style="margin-top:24px">Or enter this code in the app:</p><p style="padding:16px;background:#f3f3f3;border-radius:6px;font:600 12px monospace;word-break:break-all">${escapeHtml(token)}</p></main>`),
      text: `${message.text}\n\nCode for the app:\n${token}`,
      url,
    };
  }
  passwordReset(name: string, token: string) {
    const url = actionUrl(config.PASSWORD_RESET_URL, "/reset-password", token);
    return { ...render("Reset your password", `Hi ${name}, use this one-time link to set a new password. It expires in ${config.EMAIL_TOKEN_TTL_MINUTES} minutes.`, url, "Reset password", "If you did not request a reset, ignore this email. Your password will not change."), url };
  }
  invitation(inviter: string, token: string, expiresAt: Date) {
    const url = actionUrl(config.INVITATION_ACCEPT_URL, "/accept-invitation", token);
    return { ...render("You are invited to Personal Tracker Beta", `${inviter} invited you to Personal Tracker Beta. This invitation expires ${expiresAt.toISOString()}. Your fallback code is included below.`, url, "Accept invitation", `Fallback code: ${token}\nDo not forward this email or code.`), url };
  }
}

export class EmailService {
  private readonly renderer = new EmailTemplateRenderer();
  private readonly transport = config.EMAIL_PROVIDER === "smtp" ? nodemailer.createTransport({ host: config.SMTP_HOST, port: config.SMTP_PORT, secure: config.SMTP_SECURE === "true", auth: { user: config.SMTP_USERNAME, pass: config.SMTP_PASSWORD } }) : null;
  private async sendBrevo(input: EmailInput): Promise<DeliveryResult> {
    const response = await fetch("https://api.brevo.com/v3/smtp/email", {
      method: "POST",
      headers: { "api-key": config.BREVO_API_KEY!, "content-type": "application/json", accept: "application/json" },
      body: JSON.stringify({
        sender: { name: config.EMAIL_FROM_NAME, email: config.EMAIL_FROM },
        to: [{ email: input.to }],
        subject: input.subject,
        htmlContent: input.html,
        textContent: input.text,
      }),
      signal: AbortSignal.timeout(15_000),
    });
    if (!response.ok) throw new Error(`Brevo email delivery failed with ${response.status}`);
    const payload = await response.json().catch(() => null) as { messageId?: string } | null;
    return { status: "SENT", providerMessageId: payload?.messageId };
  }
  async send(input: EmailInput): Promise<DeliveryResult> {
    if (config.EMAIL_PROVIDER === "disabled") return { status: "FAILED" };
    if (config.EMAIL_PROVIDER === "development") {
      const outbox = join(process.cwd(), "dev-email-outbox");
      await mkdir(outbox, { recursive: true });
      const file = join(outbox, `${Date.now()}-${input.kind}.json`);
      // Local outbox intentionally contains no raw token in console output.
      await writeFile(file, JSON.stringify({ to: input.to, subject: input.subject, text: input.text, html: input.html, createdAt: new Date().toISOString() }, null, 2), "utf8");
      return { status: "DEVELOPMENT", providerMessageId: file };
    }
    try {
      if (config.EMAIL_PROVIDER === "brevo") return await this.sendBrevo(input);
      const result = await this.transport!.sendMail({ from: { address: config.EMAIL_FROM, name: config.EMAIL_FROM_NAME }, to: input.to, subject: input.subject, html: input.html, text: input.text });
      return { status: "SENT", providerMessageId: result.messageId };
    } catch {
      return { status: "FAILED" };
    }
  }
  async sendVerification(to: string, name: string, token: string) { const message = this.renderer.verification(name, token); return this.send({ to, kind: "verification", subject: "Confirm your Personal Tracker Beta email", ...message }); }
  async sendPasswordReset(to: string, name: string, token: string) { const message = this.renderer.passwordReset(name, token); return this.send({ to, kind: "password-reset", subject: "Reset your Personal Tracker password", ...message }); }
  async sendInvitation(to: string, inviter: string, token: string, expiresAt: Date) { const message = this.renderer.invitation(inviter, token, expiresAt); return this.send({ to, kind: "invitation", subject: "Invitation to Personal Tracker Beta", ...message }); }
}
