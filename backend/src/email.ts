// Transactional email via Resend. Never throws: callers get {ok:false, error}.
import { errorFields, Logger } from "./shared/http.js";

const RESEND_URL = "https://api.resend.com/emails";
const FROM = "Icos <noreply@icos.sarathfrancis.work>";

export interface EmailMessage {
  to: string | string[];
  subject: string;
  html: string;
  text?: string;
}

export interface EmailResult {
  ok: boolean;
  id?: string;
  error?: string;
}

export interface EmailOptions {
  fetch?: typeof globalThis.fetch;
  logger?: Logger;
}

export async function sendEmail(msg: EmailMessage, opts: EmailOptions = {}): Promise<EmailResult> {
  const log = opts.logger ?? new Logger("email", crypto.randomUUID());
  const key = process.env.RESEND_API_KEY;
  if (!key) {
    log.warn("RESEND_API_KEY unset; email not sent", { subject: msg.subject });
    return { ok: false, error: "RESEND_API_KEY unset" };
  }
  const doFetch = opts.fetch ?? globalThis.fetch;
  try {
    const res = await doFetch(RESEND_URL, {
      method: "POST",
      headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        from: FROM,
        to: Array.isArray(msg.to) ? msg.to : [msg.to],
        subject: msg.subject,
        html: msg.html,
        ...(msg.text === undefined ? {} : { text: msg.text }),
      }),
    });
    if (!res.ok) {
      const detail = (await res.text().catch(() => "")).slice(0, 500);
      const error = `resend responded ${res.status}`;
      log.error("email send failed", { status: res.status, detail });
      return { ok: false, error };
    }
    const body = (await res.json().catch(() => ({}))) as { id?: unknown };
    return typeof body.id === "string" ? { ok: true, id: body.id } : { ok: true };
  } catch (err) {
    log.error("email send failed", errorFields(err));
    return { ok: false, error: err instanceof Error ? err.message : String(err) };
  }
}
