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
import { Hono } from "hono";
import type { EmailMessage, EmailResult } from "../src/email.js";
import type { AuthDeps } from "../src/auth.js";

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
  let identity: typeof import("../src/identity.js");
  let makeAuth: (extra?: Partial<AuthDeps>) => import("../src/auth.js").Auth;
  let makeApp: (a: import("../src/auth.js").Auth) => typeof app;

  before(async () => {
    process.env.DATABASE_URL = TEST_DATABASE_URL;
    process.env.BETTER_AUTH_SECRET = "test-only-better-auth-secret-0123456789abcdef";
    process.env.AUTH_BASE_URL = "http://localhost";
    await applyMigrations(TEST_DATABASE_URL ?? "");
    const { createAuth } = await import("../src/auth.js");
    const { createApp } = await import("../src/index.js");
    ({ q, closePool } = await import("../src/db.js"));
    identity = await import("../src/identity.js");
    makeAuth = (extra = {}) =>
      createAuth({
        sendEmail: fakeSendEmail,
        baseURL: "http://localhost",
        secret: process.env.BETTER_AUTH_SECRET ?? "",
        ...extra,
      });
    makeApp = (a) => {
      const built = createApp(() => a);
      // A tiny /api route to exercise requireSession against this instance.
      const api = new Hono();
      api.get("/api/me", async (c) => c.json(await identity.requireSession(c, a)));
      built.route("/", api);
      return built;
    };
    auth = makeAuth();
    app = makeApp(auth);
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

  async function call(method: "GET" | "POST", path: string, body?: Json, bearer?: string, via = app) {
    const headers: Record<string, string> = { "x-forwarded-for": nextIp() };
    if (body !== undefined) headers["content-type"] = "application/json";
    if (bearer) headers.authorization = `Bearer ${bearer}`;
    const res = await via.request(`http://localhost${path}`, {
      method,
      headers,
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    const text = await res.text();
    const json = text ? (JSON.parse(text) as Json) : null;
    return { res, json };
  }

  async function signInGuest(via = app) {
    const { res, json } = await call("POST", "/auth/sign-in/anonymous", {}, undefined, via);
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

  /** Runs fn with console.error silenced (expected hook-failure logs). */
  async function quietly<T>(fn: () => Promise<T>): Promise<T> {
    const saved = console.error;
    console.error = () => {};
    try {
      return await fn();
    } finally {
      console.error = saved;
    }
  }

  function fakeIdToken(claims: Json): string {
    const b64 = (o: Json) => Buffer.from(JSON.stringify(o)).toString("base64url");
    return `${b64({ alg: "none" })}.${b64(claims)}.sig`;
  }

  async function insertAttempt(userId: string, date: string): Promise<string> {
    const pid = await puzzleId(date);
    const [row] = await q<{ id: string }>(
      `INSERT INTO public.puzzle_attempts (user_id, puzzle_id, puzzle_date, time_seconds, completed, completed_at)
       VALUES ($1, $2, $3, 42, true, now()) RETURNING id`,
      [userId, pid, date],
    );
    return row.id;
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
    const [u] = await q<{ name: string }>(`SELECT name FROM ba."user" WHERE id = $1`, [guest.id]);
    assert.equal(u.name, p.display_name, "the auth user carries the same placeholder, not 'Anonymous'");
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
    assert.equal(await identity.rekeyGuest(rekeyed.guestId, { id: String(rekeyed.user.id) }), "gone");
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
    assert.equal(claims.email, null, "no placeholder email in a guest's token");
    assert.deepEqual(Object.keys(claims).sort(), ["aud", "email", "exp", "iat", "is_anonymous", "iss", "role", "sub"]);
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

  test("a failed re-key fails the sign-up; signing in again with the guest re-keys", async () => {
    let failures = 1;
    const flaky = makeAuth({
      identity: {
        rekeyGuest: async (...args: Parameters<typeof identity.rekeyGuest>) => {
          if (failures-- > 0) throw new Error("injected re-key failure");
          return identity.rekeyGuest(...args);
        },
      },
    });
    const flakyApp = makeApp(flaky);
    const guest = await signInGuest(flakyApp);
    const attemptId = await insertAttempt(guest.id, "2001-01-03");
    const email = uniqueEmail("retry");
    const body = { name: "Rae Retry", email, password: "retry-pass" };

    const first = await quietly(() => call("POST", "/auth/sign-up/email", body, guest.token, flakyApp));
    assert.notEqual(first.res.status, 200, "the sign-up fails visibly");
    assert.equal((await profile(guest.id))?.is_anonymous, true, "guest untouched");

    const retry = await call("POST", "/auth/sign-in/email", { email, password: body.password }, guest.token, flakyApp);
    assert.equal(retry.res.status, 200, JSON.stringify(retry.json));
    const userId = String(retry.json?.user.id);
    const [moved] = await q<{ user_id: string }>("SELECT user_id FROM public.puzzle_attempts WHERE id = $1", [attemptId]);
    assert.equal(moved.user_id, userId, "guest progress re-keyed, not discarded");
    assert.equal(await profile(guest.id), undefined);
    assert.equal((await profile(userId)).is_anonymous, false);
  });

  test("a failed guest flip in account.create.after errors and writes nothing; requireSession repairs it", async () => {
    const failing = makeAuth({
      identity: {
        recordLinkedAccount: (account) =>
          identity.recordLinkedAccount(account, {
            beforeCommit: async () => {
              throw new Error("injected flip failure");
            },
          }),
      },
    });
    const guest = await signInGuest();
    const linkedEmail = uniqueEmail("linked");
    const idToken = fakeIdToken({ email: linkedEmail, email_verified: true, name: "Lee Linked" });
    const hook = failing.options.databaseHooks?.account?.create?.after as
      | ((account: unknown, ctx: null) => Promise<void>)
      | undefined;
    assert.ok(hook);
    await quietly(async () => {
      await assert.rejects(
        hook({ userId: guest.id, providerId: "google", idToken }, null),
        (err: Error) => err.name === "GuestLinkError",
      );
    });
    const [u1] = await q<Json>(`SELECT "isAnonymous", email FROM ba."user" WHERE id = $1`, [guest.id]);
    assert.equal(u1.isAnonymous, true);
    const p1 = await profile(guest.id);
    assert.equal(p1.is_anonymous, true);
    assert.equal(p1.email, null);
    assert.deepEqual(p1.providers, [], "provider append rolled back too");

    // Better Auth commits the account row before the hook runs: that is the
    // half-linked state requireSession repairs.
    await q(
      `INSERT INTO ba.account ("accountId", "providerId", "userId", "idToken", "updatedAt")
       VALUES ($1, 'google', $2, $3, now())`,
      [`google-${randomUUID()}`, guest.id, idToken],
    );
    const me = await call("GET", "/api/me", undefined, guest.token);
    assert.equal(me.res.status, 200, JSON.stringify(me.json));
    assert.deepEqual(me.json, { id: guest.id, email: linkedEmail, isAnonymous: false });
    const [u2] = await q<Json>(`SELECT "isAnonymous", email FROM ba."user" WHERE id = $1`, [guest.id]);
    assert.deepEqual({ ...u2 }, { isAnonymous: false, email: linkedEmail });
    const p2 = await profile(guest.id);
    assert.equal(p2.is_anonymous, false);
    assert.equal(p2.email, linkedEmail);
    assert.equal(p2.display_name, "Lee Linked");
    assert.deepEqual(p2.providers, ["google"]);
  });

  test("requireSession recreates a missing profile", async () => {
    const email = uniqueEmail("lost");
    const signUp = await call("POST", "/auth/sign-up/email", { name: "Lou Lost", email, password: "abcdef" });
    assert.equal(signUp.res.status, 200);
    const id = String(signUp.json?.user.id);
    const token = signUp.res.headers.get("set-auth-token") ?? "";
    await q("DELETE FROM public.profiles WHERE id = $1", [id]);
    const me = await call("GET", "/api/me", undefined, token);
    assert.equal(me.res.status, 200, JSON.stringify(me.json));
    assert.deepEqual(me.json, { id, email, isAnonymous: false });
    const p = await profile(id);
    assert.ok(p, "profile recreated");
    assert.equal(p.display_name, "Lou Lost");
    assert.equal(p.email, email);
  });

  test("requireSession: guests get no email; no session is a 401", async () => {
    const guest = await signInGuest();
    const me = await call("GET", "/api/me", undefined, guest.token);
    assert.deepEqual(me.json, { id: guest.id, email: null, isAnonymous: true });
    const anon = await call("GET", "/api/me");
    assert.equal(anon.res.status, 401);
    assert.equal(anon.json?.code, "UNAUTHORIZED");
  });

  test("discardGuest refuses a non-anonymous profile", async () => {
    const email = uniqueEmail("keep");
    const signUp = await call("POST", "/auth/sign-up/email", { name: "Kim Keep", email, password: "abcdef" });
    const id = String(signUp.json?.user.id);
    await identity.discardGuest(id);
    assert.ok(await profile(id), "a real account's profile is never discarded");
  });

  test("the ba schema is closed to the Data API roles", async () => {
    const [row] = await q<Json>(
      `SELECT has_schema_privilege('authenticated', 'ba', 'USAGE') AS authenticated,
              has_schema_privilege('anonymous', 'ba', 'USAGE') AS anonymous`,
    );
    assert.deepEqual({ ...row }, { authenticated: false, anonymous: false });
  });
});
