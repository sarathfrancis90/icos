// Shared HTTP helpers for Icos edge functions.
//
// - CORS + JSON responses
// - Structured JSON logger with a correlation id (from `x-correlation-id` or a
//   fresh UUID) that is echoed back on every response.
// - Auth helpers: getUser(req) (user JWT), requireServiceRole(req) (service key
//   bearer), banCheck(admin, userId).
// - Small date/crypto utilities shared by start-puzzle / submit-score.

import { createClient, type SupabaseClient } from "@supabase/supabase-js";

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
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
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
// Supabase clients + auth
// ---------------------------------------------------------------------------
function env(name: string): string {
  const v = Deno.env.get(name);
  if (!v) throw new Error(`Missing required env var ${name}`);
  return v;
}

export function adminClient(): SupabaseClient {
  return createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

export function userClient(authHeader: string): SupabaseClient {
  return createClient(env("SUPABASE_URL"), env("SUPABASE_ANON_KEY"), {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

export function bearerToken(req: Request): string | null {
  const h = req.headers.get("Authorization") ?? req.headers.get("authorization");
  if (!h) return null;
  const m = /^Bearer\s+(.+)$/i.exec(h.trim());
  return m ? m[1].trim() : null;
}

export interface AuthedUser {
  id: string;
  email: string | null;
  isAnonymous: boolean;
}

/** Resolve the caller from a user JWT. Returns null when missing/invalid. */
export async function getUser(req: Request): Promise<AuthedUser | null> {
  const token = bearerToken(req);
  if (!token) return null;
  try {
    const client = userClient(`Bearer ${token}`);
    const { data, error } = await client.auth.getUser(token);
    if (error || !data.user) return null;
    return {
      id: data.user.id,
      email: data.user.email ?? null,
      isAnonymous: Boolean((data.user as { is_anonymous?: boolean }).is_anonymous),
    };
  } catch {
    return null;
  }
}

/** True when the bearer token IS the service-role key (constant-time compare). */
export function requireServiceRole(req: Request): boolean {
  const token = bearerToken(req);
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!token || !key) return false;
  return timingSafeEqual(token, key);
}

export function timingSafeEqual(a: string, b: string): boolean {
  const ea = new TextEncoder().encode(a);
  const eb = new TextEncoder().encode(b);
  if (ea.length !== eb.length) return false;
  let diff = 0;
  for (let i = 0; i < ea.length; i++) diff |= ea[i] ^ eb[i];
  return diff === 0;
}

export interface ProfileGate {
  id: string;
  is_banned: boolean;
  is_anonymous: boolean;
  deleted_at: string | null;
  display_name: string;
}

export type BanCheckResult =
  | { ok: true; profile: ProfileGate }
  | { ok: false; status: number; code: string; message: string };

/** Loads the profile and rejects banned / deletion-pending / missing users. */
export async function banCheck(
  admin: SupabaseClient,
  userId: string,
): Promise<BanCheckResult> {
  const { data, error } = await admin
    .from("profiles")
    .select("id, is_banned, is_anonymous, deleted_at, display_name")
    .eq("id", userId)
    .maybeSingle();
  if (error) {
    return { ok: false, status: 500, code: "PROFILE_LOOKUP_FAILED", message: "Could not load profile" };
  }
  if (!data) {
    return { ok: false, status: 403, code: "PROFILE_NOT_FOUND", message: "Profile not found" };
  }
  const profile = data as ProfileGate;
  if (profile.is_banned) {
    return { ok: false, status: 403, code: "BANNED", message: "Account suspended" };
  }
  if (profile.deleted_at) {
    return { ok: false, status: 403, code: "DELETED", message: "Account scheduled for deletion" };
  }
  return { ok: true, profile };
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
