// Shared harness for the /api/* route tests: an app wired to a Better Auth
// instance and email stubs that record what would have been sent, a silent
// logger, and helpers to create guest / email sessions over HTTP.
// Import only after process.env has the test DATABASE_URL etc. (setupApi does it).
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { TEST_DATABASE_URL } from "./env.js";
import type { EmailMessage, EmailResult } from "../../src/email.js";
import { Logger } from "../../src/shared/http.js";

export type Json = Record<string, any>;

/** A Logger that prints nothing (keeps test output pristine). */
export class SilentLogger extends Logger {
  override child(): Logger {
    return this;
  }
  override debug(): void {}
  override info(): void {}
  override warn(): void {}
  override error(): void {}
}

export interface ApiHarness {
  /** Emails the /api routes sent (report alerts). */
  routeEmails: EmailMessage[];
  /** Emails Better Auth sent (verification, reset). */
  authEmails: EmailMessage[];
  call(method: string, path: string, body?: unknown, bearer?: string): Promise<{ res: Response; json: Json | null }>;
  signInGuest(): Promise<{ id: string; token: string }>;
  signUpEmail(tag?: string): Promise<{ id: string; token: string; email: string }>;
  uniqueEmail(tag: string): string;
  q: typeof import("../../src/db.js").q;
  close(): Promise<void>;
}

export const SKIP = TEST_DATABASE_URL ? false : "NEON_TEST_DATABASE_URL not set";

export async function setupApi(): Promise<ApiHarness> {
  process.env.DATABASE_URL = TEST_DATABASE_URL;
  process.env.BETTER_AUTH_SECRET = "test-only-better-auth-secret-0123456789abcdef";
  process.env.AUTH_BASE_URL = "http://localhost";
  process.env.PUZZLE_SEED_SALT = "test-salt";
  const { applyMigrations } = await import("../../scripts/migrate.js");
  await applyMigrations(TEST_DATABASE_URL ?? "");
  const { createAuth } = await import("../../src/auth.js");
  const { createApp } = await import("../../src/index.js");
  const { q, closePool } = await import("../../src/db.js");

  const routeEmails: EmailMessage[] = [];
  const authEmails: EmailMessage[] = [];
  const record =
    (into: EmailMessage[]) =>
    async (msg: EmailMessage): Promise<EmailResult> => {
      into.push(msg);
      return { ok: true, id: `fake-${into.length}` };
    };
  const auth = createAuth({
    sendEmail: record(authEmails),
    baseURL: "http://localhost",
    secret: process.env.BETTER_AUTH_SECRET,
  });
  const app = createApp(() => auth, {
    sendEmail: record(routeEmails),
    logger: (fn, cid) => new SilentLogger(fn, cid),
  });

  // A distinct client IP per call keeps Better Auth's per-IP rate limits away.
  let ipCounter = 0;
  const nextIp = () => {
    ipCounter += 1;
    return `10.${Math.floor(Math.random() * 200)}.${Math.floor(ipCounter / 250)}.${(ipCounter % 250) + 1}`;
  };

  async function call(method: string, path: string, body?: unknown, bearer?: string) {
    const headers: Record<string, string> = { "x-forwarded-for": nextIp() };
    if (body !== undefined) headers["content-type"] = "application/json";
    if (bearer) headers.authorization = `Bearer ${bearer}`;
    const res = await app.request(`http://localhost${path}`, {
      method,
      headers,
      body: body === undefined ? undefined : typeof body === "string" ? body : JSON.stringify(body),
    });
    const text = await res.text();
    let json: Json | null = null;
    if (text) {
      try {
        json = JSON.parse(text) as Json;
      } catch {
        json = { raw: text };
      }
    }
    return { res, json };
  }

  const uniqueEmail = (tag: string) => `${tag}-${randomUUID().slice(0, 8)}@example.com`;

  async function signInGuest() {
    const { res, json } = await call("POST", "/auth/sign-in/anonymous", {});
    assert.equal(res.status, 200, JSON.stringify(json));
    const token = res.headers.get("set-auth-token");
    assert.ok(token, "set-auth-token header");
    return { id: String(json?.user.id), token };
  }

  async function signUpEmail(tag = "member") {
    const email = uniqueEmail(tag);
    const { res, json } = await call("POST", "/auth/sign-up/email", { email, password: "secret-pass-1", name: "Member" });
    assert.equal(res.status, 200, JSON.stringify(json));
    const token = res.headers.get("set-auth-token");
    assert.ok(token, "set-auth-token header");
    return { id: String(json?.user.id), token, email };
  }

  return { routeEmails, authEmails, call, signInGuest, signUpEmail, uniqueEmail, q, close: closePool };
}
