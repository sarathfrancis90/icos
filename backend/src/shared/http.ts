// Shared HTTP helpers for the Icos API (ported from the edge functions'
// `_shared/http.ts`).
//
// - CORS + JSON responses
// - Structured JSON logger with a correlation id (from `x-correlation-id` or a
//   fresh UUID) that is echoed back on every response.
// - bearerToken(req) and a constant-time string compare; user / service auth
//   lives in the auth middleware.
// - Small date/crypto utilities shared by start-puzzle / submit-score. Crypto
//   uses the Web Crypto API Node exposes globally (`crypto.subtle`,
//   `crypto.randomUUID`, `crypto.getRandomValues`).

export const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-correlation-id",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

export const CORRELATION_HEADER = "x-correlation-id";

export function correlationIdFrom(req: Request): string {
  const supplied = req.headers.get(CORRELATION_HEADER)?.trim();
  if (supplied && /^[A-Za-z0-9._:-]{1,128}$/.test(supplied)) return supplied;
  return crypto.randomUUID();
}

// ---------------------------------------------------------------------------
// Logger
// ---------------------------------------------------------------------------
export type LogLevel = "debug" | "info" | "warn" | "error";

export class Logger {
  constructor(
    readonly fn: string,
    readonly correlationId: string,
    private readonly base: Record<string, unknown> = {},
  ) {}

  child(fields: Record<string, unknown>): Logger {
    return new Logger(this.fn, this.correlationId, { ...this.base, ...fields });
  }

  private emit(level: LogLevel, msg: string, fields?: Record<string, unknown>) {
    const line = JSON.stringify({
      ts: new Date().toISOString(),
      level,
      fn: this.fn,
      correlation_id: this.correlationId,
      msg,
      ...this.base,
      ...(fields ?? {}),
    });
    if (level === "error") console.error(line);
    else if (level === "warn") console.warn(line);
    else console.log(line);
  }

  debug(msg: string, fields?: Record<string, unknown>) { this.emit("debug", msg, fields); }
  info(msg: string, fields?: Record<string, unknown>) { this.emit("info", msg, fields); }
  warn(msg: string, fields?: Record<string, unknown>) { this.emit("warn", msg, fields); }
  error(msg: string, fields?: Record<string, unknown>) { this.emit("error", msg, fields); }
}

export function errorFields(err: unknown): Record<string, unknown> {
  if (err instanceof Error) {
    return { error: err.message, error_name: err.name, stack: err.stack };
  }
  return { error: String(err) };
}

// ---------------------------------------------------------------------------
// Responses
// ---------------------------------------------------------------------------
export function json(
  body: unknown,
  status = 200,
  extraHeaders: Record<string, string> = {},
): Response {
  // No CORS headers here: the app's cors() middleware (src/index.ts) owns them,
  // so only the website's origin is ever allowed.
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      ...extraHeaders,
    },
  });
}

export function errorResponse(
  status: number,
  message: string,
  code: string,
  correlationId: string,
  extra: Record<string, unknown> = {},
): Response {
  return json({ error: message, code, ...extra }, status, {
    [CORRELATION_HEADER]: correlationId,
  });
}

/** Handles OPTIONS preflight and GET /health. Returns null for everything else. */
export function handleCommon(req: Request, fn: string): Response | null {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  const url = new URL(req.url);
  if (url.pathname.endsWith("/health")) {
    return json({ status: "ok", fn, ts: new Date().toISOString() });
  }
  return null;
}

// ---------------------------------------------------------------------------
// Request credentials
// ---------------------------------------------------------------------------
export function bearerToken(req: Request): string | null {
  const h = req.headers.get("Authorization") ?? req.headers.get("authorization");
  if (!h) return null;
  const m = /^Bearer\s+(.+)$/i.exec(h.trim());
  return m ? m[1].trim() : null;
}

export function timingSafeEqual(a: string, b: string): boolean {
  const ea = new TextEncoder().encode(a);
  const eb = new TextEncoder().encode(b);
  if (ea.length !== eb.length) return false;
  let diff = 0;
  for (let i = 0; i < ea.length; i++) diff |= ea[i] ^ eb[i];
  return diff === 0;
}

// ---------------------------------------------------------------------------
// Validation helpers
// ---------------------------------------------------------------------------
export async function readJson(req: Request): Promise<Record<string, unknown> | null> {
  try {
    const text = await req.text();
    if (!text.trim()) return {};
    const parsed = JSON.parse(text);
    if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) return null;
    return parsed as Record<string, unknown>;
  } catch {
    return null;
  }
}

export function isInt(v: unknown, min: number, max: number): v is number {
  return typeof v === "number" && Number.isInteger(v) && v >= min && v <= max;
}

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

/** True for a well-formed, real calendar date string (YYYY-MM-DD). */
export function isIsoDate(v: unknown): v is string {
  if (typeof v !== "string" || !DATE_RE.test(v)) return false;
  const d = new Date(`${v}T00:00:00Z`);
  return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === v;
}

export function utcToday(): string {
  return new Date().toISOString().slice(0, 10);
}

export function addDays(date: string, days: number): string {
  const d = new Date(`${date}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}

export function compareDates(a: string, b: string): number {
  return a < b ? -1 : a > b ? 1 : 0;
}

/**
 * How many days back a puzzle stays playable (and scorable) from the archive.
 * Shared by start-puzzle and submit-score so the two can never disagree; the
 * store listing promises "the last 30 days".
 */
export const ARCHIVE_WINDOW_DAYS = 30;

/** True when `date` is between `today - ARCHIVE_WINDOW_DAYS` and `today`, inclusive. */
export function isWithinArchiveWindow(date: string, today: string): boolean {
  return compareDates(date, today) <= 0 &&
    compareDates(date, addDays(today, -ARCHIVE_WINDOW_DAYS)) >= 0;
}

// ---------------------------------------------------------------------------
// Crypto
// ---------------------------------------------------------------------------
function toHex(buf: ArrayBuffer): string {
  return Array.from(new Uint8Array(buf))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

export async function sha256Hex(input: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(input));
  return toHex(digest);
}

export async function hmacSha256Hex(key: string, message: string): Promise<string> {
  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(key),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", cryptoKey, new TextEncoder().encode(message));
  return toHex(sig);
}

export function randomNonce(bytes = 32): string {
  const buf = new Uint8Array(bytes);
  crypto.getRandomValues(buf);
  return toHex(buf.buffer);
}

/** Canonical HMAC message for a score submission (must match the Dart client). */
export function scoreMessage(
  puzzleDate: string,
  timeSeconds: number,
  hintsUsed: number,
  undosUsed: number,
  pathHashHex: string,
): string {
  return `${puzzleDate}|${timeSeconds}|${hintsUsed}|${undosUsed}|${pathHashHex}`;
}
