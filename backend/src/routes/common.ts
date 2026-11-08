// Shared plumbing for the /api/* routers (the former edge functions):
// dependencies, the signed-in + not-banned gate, responses with the
// correlation id, and the report alert email.
import type { Context } from "hono";
import type { Auth } from "../auth.js";
import type { EmailMessage, EmailResult } from "../email.js";
import { q } from "../db.js";
import { banCheck, requireSession, type ProfileGate, type SessionUser } from "../identity.js";
import { CORRELATION_HEADER, correlationIdFrom, errorResponse, json, Logger } from "../shared/http.js";

export interface ApiDeps {
  auth: () => Auth;
  sendEmail: (msg: EmailMessage) => Promise<EmailResult>;
  /** Builds the structured logger for one request (tests pass a silent one). */
  logger: (fn: string, correlationId: string) => Logger;
}

export const DEFAULT_REPORT_ALERT_TO = "sarathfrancis90@gmail.com";

export const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Per-request context: correlation id, logger and response helpers. */
export interface RequestCtx {
  cid: string;
  log: Logger;
  ok: (body: unknown, status?: number, headers?: Record<string, string>) => Response;
  fail: (status: number, message: string, code: string, extra?: Record<string, unknown>) => Response;
  /** 400 INVALID_FIELD naming the field (the edge functions' `bad(field)`). */
  bad: (field: string) => Response;
}

export function requestCtx(c: Context, deps: ApiDeps, fn: string): RequestCtx {
  const cid = correlationIdFrom(c.req.raw);
  const fail: RequestCtx["fail"] = (status, message, code, extra = {}) =>
    errorResponse(status, message, code, cid, extra);
  return {
    cid,
    log: deps.logger(fn, cid),
    ok: (body, status = 200, headers = {}) => json(body, status, { [CORRELATION_HEADER]: cid, ...headers }),
    fail,
    bad: (field) => fail(400, `Invalid or missing field: ${field}`, "INVALID_FIELD", { field }),
  };
}

export function methodNotAllowed(r: RequestCtx): Response {
  return r.fail(405, "Method not allowed", "METHOD_NOT_ALLOWED");
}

export interface ActiveUser {
  user: SessionUser;
  profile: ProfileGate;
}

/**
 * The session user, provided the profile exists and is neither banned nor
 * pending deletion; otherwise the rejection to return. No session throws the
 * 401 HTTPException from requireSession (passed through by app.onError).
 */
export async function activeUser(c: Context, deps: ApiDeps, r: RequestCtx): Promise<ActiveUser | Response> {
  const user = await requireSession(c, deps.auth());
  const gate = await banCheck(user.id);
  if (!gate.ok) {
    r.log.warn("caller rejected", { user_id: user.id, code: gate.code });
    return r.fail(gate.status, gate.message, gate.code);
  }
  return { user, profile: gate.profile };
}

/** Marks the user active now (feeds the 90-day inactive-guest purge). */
export async function touchLastActive(userId: string): Promise<void> {
  await q("UPDATE public.profiles SET last_active_at = now() WHERE id = $1", [userId]);
}

export interface ReportRow {
  id: string;
  reporter_id: string;
  reported_user_id: string | null;
  reported_group_id: string | null;
  reason: string;
  details: string;
  created_at: Date;
}

function escapeHtml(s: string): string {
  return s.replace(/[&<>"']/g, (ch) => `&#${ch.charCodeAt(0)};`);
}

/** The alert the Supabase-era notify_report_filed trigger sent (same subject and text). */
export function reportAlert(report: ReportRow, to: string): EmailMessage {
  const label = report.reported_group_id
    ? `group ${report.reported_group_id}`
    : report.reported_user_id
      ? `user ${report.reported_user_id}`
      : "unknown target";
  const filedAt = new Date(report.created_at).toISOString().slice(0, 16).replace("T", " ");
  const text =
    "A report was filed in Icos.\n\n" +
    `Report id: ${report.id}\n` +
    `Reason: ${report.reason}\n` +
    `Target: ${label}\n` +
    `Reporter: ${report.reporter_id}\n` +
    `Details: ${report.details === "" ? "(none)" : report.details}\n` +
    `Filed at: ${filedAt} UTC\n\n` +
    "Review within 24 hours: Neon Console > Tables > reports, then set status.";
  return {
    to,
    subject: `Icos report: ${report.reason} (${label})`,
    text,
    html: `<pre style="font-family:monospace;white-space:pre-wrap">${escapeHtml(text)}</pre>`,
  };
}

/** Emails the owner about a new report. Never throws (sendEmail does not). */
export async function notifyReportFiled(deps: ApiDeps, report: ReportRow, log: Logger): Promise<void> {
  const to = process.env.REPORT_ALERT_TO || DEFAULT_REPORT_ALERT_TO;
  const result = await deps.sendEmail(reportAlert(report, to));
  if (!result.ok) log.warn("report alert not sent", { report_id: report.id, error: result.error });
}

/** Postgres error fields pg exposes on a DatabaseError. */
export function pgError(err: unknown): { code?: string; hint?: string; constraint?: string } {
  return err && typeof err === "object" ? (err as { code?: string; hint?: string; constraint?: string }) : {};
}
