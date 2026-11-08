// Better Auth over HTTP (Hono app.request) against the Neon `test` branch:
// guest sign-in, guest -> account re-keying, sign-in to an existing account,
// JWT/JWKS, and the emails Better Auth asks us to send.
// Users created here persist (Better Auth commits its own writes); every email
// is unique per run, so reruns do not collide. Reset the branch to clean up.
// Skips (does not fail) when NEON_TEST_DATABASE_URL is not set.
import { after, before, describe, test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { decodeJwt, decodeProtectedHeader } from "jose";
import { TEST_DATABASE_URL } from "./helpers/env.js";
import { applyMigrations } from "../scripts/migrate.js";
import type { EmailMessage, EmailResult } from "../src/email.js";

type Json = Record<string, any>;

describe("Better Auth HTTP", { skip: TEST_DATABASE_URL ? false : "NEON_TEST_DATABASE_URL not set" }, () => {
  const sent: EmailMessage[] = [];
  const fakeSendEmail = async (msg: EmailMessage): Promise<EmailResult> => {
    sent.push(msg);
    return { ok: true, id: `fake-${sent.length}` };
  };

  let app: { request: (path: string, init?: RequestInit) => Response | Promise<Response> };
  let auth: import("../src/auth.js").Auth;
  let q: typeof import("../src/db.js").q;
  let closePool: typeof import("../src/db.js").closePool;

  before(async () => {
    process.env.DATABASE_URL = TEST_DATABASE_URL;
    process.env.BETTER_AUTH_SECRET = "test-only-better-auth-secret-0123456789abcdef";
    process.env.AUTH_BASE_URL = "http://localhost";
    await applyMigrations(TEST_DATABASE_URL ?? "");
    const { createAuth } = await import("../src/auth.js");
    const { createApp } = await import("../src/index.js");
    ({ q, closePool } = await import("../src/db.js"));
    auth = createAuth({
      sendEmail: fakeSendEmail,
      baseURL: "http://localhost",
      secret: process.env.BETTER_AUTH_SECRET,
    });
    app = createApp(() => auth);
  });

  after(async () => {
    await closePool?.();
  });

  // --- helpers --------------------------------------------------------------
  // A distinct client IP per call keeps Better Auth's rate limits (3 email
  // sign-ins per 10 s per IP) out of the way.
  let ipCounter = 0;
  function nextIp(): string {
    ipCounter += 1;
    return `10.${Math.floor(Math.random() * 200)}.${Math.floor(ipCounter / 250)}.${(ipCounter % 250) + 1}`;
  }

  async function call(method: "GET" | "POST", path: string, body?: Json, bearer?: string) {
    const headers: Record<string, string> = { "x-forwarded-for": nextIp() };
    if (body !== undefined) headers["content-type"] = "application/json";
    if (bearer) headers.authorization = `Bearer ${bearer}`;
    const res = await app.request(`http://localhost${path}`, {
      method,
      headers,
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    const text = await res.text();
    const json = text ? (JSON.parse(text) as Json) : null;
    return { res, json };
  }

  async function signInGuest() {
    const { res, json } = await call("POST", "/auth/sign-in/anonymous", {});
    assert.equal(res.status, 200, JSON.stringify(json));
    const token = res.headers.get("set-auth-token");
    assert.ok(token, "set-auth-token header");
    return { id: String(json?.user.id), token };
  }

  function uniqueEmail(tag: string): string {
    return `${tag}-${randomUUID().slice(0, 8)}@example.com`;
  }

  async function profile(id: string) {
    const rows = await q<Json>("SELECT * FROM public.profiles WHERE id = $1", [id]);
    return rows[0];
  }

  async function puzzleId(date: string): Promise<string> {
    await q(
      `INSERT INTO public.puzzles (puzzle_date, grid_size, waypoints, difficulty, par_time_seconds)
       VALUES ($1, 5, '[]'::jsonb, 'easy', 60) ON CONFLICT (puzzle_date) DO NOTHING`,
      [date],
    );
    const [row] = await q<{ id: string }>("SELECT id FROM public.puzzles WHERE puzzle_date = $1", [date]);
    return row.id;
  }

  async function waitForEmail(to: string, subject: string): Promise<EmailMessage> {
    for (let i = 0; i < 50; i++) {
      const found = sent.find((m) => m.to === to && m.subject === subject);
      if (found) return found;
      await new Promise((r) => setTimeout(r, 50));
    }
    assert.fail(`no "${subject}" email to ${to}`);
  }

  const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

  // --- cases ------------------------------------------------------------------
  test("anonymous sign-in creates a guest profile with a placeholder name", async () => {
    const guest = await signInGuest();
    assert.match(guest.id, UUID);
    const p = await profile(guest.id);
    assert.ok(p, "profile row");
    assert.equal(p.is_anonymous, true);
    assert.match(p.display_name, /^Player \d{4}$/);
    assert.equal(p.email, null);
  });

  let rekeyed: { guestId: string; user: Json } | undefined;

  test("sign-up with the guest bearer re-keys the guest's profile and progress", async () => {
    const guest = await signInGuest();
    const pid = await puzzleId("2001-01-01");
    const [attempt] = await q<{ id: string }>(
      `INSERT INTO public.puzzle_attempts (user_id, puzzle_id, puzzle_date, time_seconds, completed, completed_at)
       VALUES ($1, $2, '2001-01-01', 42, true, now()) RETURNING id`,
      [guest.id, pid],
    );

    const email = uniqueEmail("upgrade");
    const { res, json } = await call(
      "POST",
      "/auth/sign-up/email",
      { name: "Jane Doe", email, password: "secret-pass" },
      guest.token,
    );
    assert.equal(res.status, 200, JSON.stringify(json));
    const user = json?.user as Json;
    assert.match(user.id, UUID);
    assert.notEqual(user.id, guest.id);

    const rows = await q<Json>("SELECT * FROM public.profiles WHERE id = ANY($1::uuid[])", [[guest.id, user.id]]);
    assert.equal(rows.length, 1);
    const p = rows[0];
    assert.equal(p.id, user.id);
    assert.equal(p.is_anonymous, false);
    assert.equal(p.email, email);
    assert.equal(p.display_name, "Jane Doe");
    assert.deepEqual(p.providers, ["credential"]);

    const [moved] = await q<{ user_id: string }>("SELECT user_id FROM public.puzzle_attempts WHERE id = $1", [attempt.id]);
    assert.equal(moved.user_id, user.id);
    const guestAuthRows = await q(`SELECT 1 FROM ba."user" WHERE id = $1`, [guest.id]);
    assert.equal(guestAuthRows.length, 0, "the plugin deletes the guest's auth user");
    rekeyed = { guestId: guest.id, user };
  });

  test("link_twice_is_noop", async () => {
    assert.ok(rekeyed, "depends on the re-key test");
    const plugin = auth.options.plugins?.find((p) => p.id === "anonymous") as
      | { options?: { onLinkAccount?: (data: unknown) => Promise<void> } }
      | undefined;
    const onLinkAccount = plugin?.options?.onLinkAccount;
    assert.ok(onLinkAccount, "anonymous plugin exposes onLinkAccount");
    const [{ n: before }] = await q<{ n: number }>("SELECT count(*)::int AS n FROM public.profiles");
    await onLinkAccount({
      anonymousUser: { user: { id: rekeyed.guestId, isAnonymous: true }, session: {} },
      newUser: { user: { ...rekeyed.user, createdAt: new Date(rekeyed.user.createdAt) }, session: {} },
      ctx: {},
    });
    const [{ n: afterCount }] = await q<{ n: number }>("SELECT count(*)::int AS n FROM public.profiles");
    assert.equal(afterCount, before);
    const p = await profile(rekeyed.user.id);
    assert.equal(p.is_anonymous, false);
  });

  test("existing_account_discards_guest", async () => {
    const email = uniqueEmail("existing");
    const password = "existing-pass";
    const signUp = await call("POST", "/auth/sign-up/email", { name: "Alex Existing", email, password });
    assert.equal(signUp.res.status, 200, JSON.stringify(signUp.json));
    const accountId = String(signUp.json?.user.id);
    await q(
      `INSERT INTO public.streaks (user_id, current_streak, longest_streak, last_solve_date)
       VALUES ($1, 7, 9, '2001-01-02')`,
      [accountId],
    );

    const guest = await signInGuest();
    const signIn = await call("POST", "/auth/sign-in/email", { email, password }, guest.token);
    assert.equal(signIn.res.status, 200, JSON.stringify(signIn.json));
    assert.equal(signIn.json?.user.id, accountId);

    const [streak] = await q<Json>("SELECT current_streak, longest_streak FROM public.streaks WHERE user_id = $1", [
      accountId,
    ]);
    assert.deepEqual({ ...streak }, { current_streak: 7, longest_streak: 9 });
    assert.equal(await profile(guest.id), undefined, "guest profile is gone");
    const a = await profile(accountId);
    assert.equal(a.display_name, "Alex Existing");
    assert.equal(a.is_anonymous, false);
  });

  test("sign-up without a guest creates a profile named after the account", async () => {
    const email = uniqueEmail("fresh");
    const { res, json } = await call("POST", "/auth/sign-up/email", { name: "Sam Fresh", email, password: "abcdef" });
    assert.equal(res.status, 200, JSON.stringify(json));
    const p = await profile(String(json?.user.id));
    assert.ok(p, "profile row");
    assert.equal(p.display_name, "Sam Fresh");
    assert.equal(p.is_anonymous, false);
    assert.equal(p.email, email);
    assert.equal(p.email_verified, false);
    assert.deepEqual(p.providers, ["credential"]);
  });

  test("sign-up sends the verification email", async () => {
    const email = uniqueEmail("verify");
    const { res } = await call("POST", "/auth/sign-up/email", { name: "Vera", email, password: "abcdef" });
    assert.equal(res.status, 200);
    const msg = await waitForEmail(email, "Confirm your Icos email");
    const link = /href="([^"]+)"/.exec(msg.html)?.[1]?.replace(/&#38;/g, "&");
    assert.ok(link, "link in the html");
    const url = new URL(link);
    assert.equal(url.pathname, "/auth/verify-email");
    assert.ok(url.searchParams.get("token"));
    assert.equal(url.searchParams.get("callbackURL"), "https://icos.sarathfrancis.work/verified");
    assert.ok(msg.text?.includes("/auth/verify-email?token="));
  });

  test("a reset request emails a /reset?token= link", async () => {
    const email = uniqueEmail("reset");
    const signUp = await call("POST", "/auth/sign-up/email", { name: "Rita", email, password: "abcdef" });
    assert.equal(signUp.res.status, 200);
    const { res, json } = await call("POST", "/auth/request-password-reset", { email });
    assert.equal(res.status, 200, JSON.stringify(json));
    const msg = await waitForEmail(email, "Reset your Icos password");
    assert.ok(msg.html.includes("https://icos.sarathfrancis.work/reset?token="));
    assert.ok(msg.text?.includes("https://icos.sarathfrancis.work/reset?token="));
  });

  test("/auth/token returns an ES256 JWT with the Data API claims", async () => {
    const guest = await signInGuest();
    const { res, json } = await call("GET", "/auth/token", undefined, guest.token);
    assert.equal(res.status, 200, JSON.stringify(json));
    const token = String(json?.token);
    assert.equal(decodeProtectedHeader(token).alg, "ES256");
    const claims = decodeJwt(token);
    assert.equal(claims.sub, guest.id);
    assert.equal(claims.role, "authenticated");
    assert.equal(claims.is_anonymous, true);
    assert.ok(typeof claims.exp === "number" && claims.exp - Math.floor(Date.now() / 1000) <= 15 * 60);
  });

  test("/auth/jwks serves one ES256 key", async () => {
    const { res, json } = await call("GET", "/auth/jwks");
    assert.equal(res.status, 200);
    const keys = json?.keys as Json[];
    assert.equal(keys.length, 1);
    assert.equal(keys[0].alg, "ES256");
    assert.equal(keys[0].kty, "EC");
    assert.equal(keys[0].crv, "P-256");
    assert.ok(keys[0].kid);
    assert.equal(keys[0].d, undefined, "no private key material");
  });
});
