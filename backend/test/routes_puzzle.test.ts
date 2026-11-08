// /api/start-puzzle and /api/daily-puzzle over HTTP against the Neon `test`
// branch, plus generateForDate (the cron path). Skips without NEON_TEST_DATABASE_URL.
import { after, before, describe, test } from "node:test";
import assert from "node:assert/strict";
import { setupApi, SilentLogger, SKIP, type ApiHarness } from "./helpers/api.js";
import { addDays, utcToday } from "../src/shared/http.js";

describe("puzzle routes", { skip: SKIP }, () => {
  let h: ApiHarness;
  let generateForDate: typeof import("../src/routes/puzzle.js").generateForDate;

  before(async () => {
    h = await setupApi();
    ({ generateForDate } = await import("../src/routes/puzzle.js"));
  });
  after(async () => {
    await h?.close();
  });

  async function stubPuzzle(date: string): Promise<void> {
    await h.q(
      `INSERT INTO public.puzzles (puzzle_date, grid_size, waypoints, difficulty, par_time_seconds)
       VALUES ($1, 5, '[]'::jsonb, 'easy', 60) ON CONFLICT (puzzle_date) DO NOTHING`,
      [date],
    );
  }

  describe("POST /api/start-puzzle", () => {
    test("401 without a session", async () => {
      const { res, json } = await h.call("POST", "/api/start-puzzle", { puzzle_date: utcToday() });
      assert.equal(res.status, 401);
      assert.equal(json?.code, "UNAUTHORIZED");
    });

    test("404 PUZZLE_NOT_FOUND for a date without a puzzle", async () => {
      const guest = await h.signInGuest();
      const date = addDays(utcToday(), -28);
      await h.q("DELETE FROM public.puzzles WHERE puzzle_date = $1", [date]);
      const { res, json } = await h.call("POST", "/api/start-puzzle", { puzzle_date: date }, guest.token);
      assert.equal(res.status, 404);
      assert.deepEqual(json, { error: "No puzzle for that date", code: "PUZZLE_NOT_FOUND" });
      assert.ok(res.headers.get("x-correlation-id"));
    });

    test("400 for a malformed or out-of-window date", async () => {
      const guest = await h.signInGuest();
      const bad = await h.call("POST", "/api/start-puzzle", { puzzle_date: "2026-13-01" }, guest.token);
      assert.equal(bad.res.status, 400);
      assert.equal(bad.json?.code, "INVALID_DATE");
      const future = await h.call("POST", "/api/start-puzzle", { puzzle_date: addDays(utcToday(), 1) }, guest.token);
      assert.equal(future.res.status, 400);
      assert.equal(future.json?.code, "DATE_OUT_OF_RANGE");
    });

    test("200 with a 64-hex nonce; a second call returns the same nonce and started_at", async () => {
      const guest = await h.signInGuest();
      const date = addDays(utcToday(), -25);
      await stubPuzzle(date);
      const first = await h.call("POST", "/api/start-puzzle", { puzzle_date: date }, guest.token);
      assert.equal(first.res.status, 200, JSON.stringify(first.json));
      assert.equal(first.json?.puzzle_date, date);
      assert.match(String(first.json?.nonce), /^[0-9a-f]{64}$/);
      assert.equal(first.json?.already_completed, false);
      assert.ok(!Number.isNaN(Date.parse(String(first.json?.started_at))));

      const second = await h.call("POST", "/api/start-puzzle", { puzzle_date: date }, guest.token);
      assert.equal(second.res.status, 200);
      assert.equal(second.json?.nonce, first.json?.nonce);
      assert.equal(second.json?.started_at, first.json?.started_at);
    });

    test("405 for GET", async () => {
      const { res, json } = await h.call("GET", "/api/start-puzzle");
      assert.equal(res.status, 405);
      assert.equal(json?.code, "METHOD_NOT_ALLOWED");
    });
  });

  describe("POST /api/daily-puzzle", () => {
    test("403 DATE_NOT_ALLOWED for today+2", async () => {
      const guest = await h.signInGuest();
      const { res, json } = await h.call("POST", "/api/daily-puzzle", { date: addDays(utcToday(), 2) }, guest.token);
      assert.equal(res.status, 403);
      assert.equal(json?.code, "DATE_NOT_ALLOWED");
    });

    test("201 created, then 200 exists for tomorrow; no solution in the response", async () => {
      const guest = await h.signInGuest();
      const tomorrow = addDays(utcToday(), 1);
      await h.q("DELETE FROM public.puzzles WHERE puzzle_date = $1", [tomorrow]);

      const first = await h.call("POST", "/api/daily-puzzle", {}, guest.token);
      assert.equal(first.res.status, 201, JSON.stringify(first.json));
      assert.equal(first.json?.status, "created");
      assert.equal(first.json?.puzzle_date, tomorrow);
      assert.equal(first.json?.puzzle.puzzle_date, tomorrow);
      assert.equal(first.json?.puzzle.seed_version, 3);
      assert.ok(Array.isArray(first.json?.puzzle.waypoints));
      assert.equal(JSON.stringify(first.json).includes("path"), false);

      const [sol] = await h.q<{ n: number }>(
        "SELECT count(*)::int AS n FROM public.puzzle_solutions WHERE puzzle_id = $1",
        [first.json?.puzzle.id],
      );
      assert.equal(sol.n, 1);

      const second = await h.call("POST", "/api/daily-puzzle", { date: tomorrow }, guest.token);
      assert.equal(second.res.status, 200);
      assert.equal(second.json?.status, "exists");
      assert.equal(second.json?.puzzle.id, first.json?.puzzle.id);
    });

    test("500 MISSING_SEED_SALT when the salt is not configured", async () => {
      const guest = await h.signInGuest();
      const saved = process.env.PUZZLE_SEED_SALT;
      delete process.env.PUZZLE_SEED_SALT;
      try {
        const { res, json } = await h.call("POST", "/api/daily-puzzle", {}, guest.token);
        assert.equal(res.status, 500);
        assert.equal(json?.code, "MISSING_SEED_SALT");
      } finally {
        process.env.PUZZLE_SEED_SALT = saved;
      }
    });
  });

  describe("generateForDate (cron path)", () => {
    test("creates any date from 2026-01-01, then reports exists", async () => {
      const date = "2026-01-05";
      await h.q("DELETE FROM public.puzzles WHERE puzzle_date = $1", [date]);
      const log = new SilentLogger("daily-puzzle", "test");
      assert.equal(await generateForDate(date, log), "created");
      assert.equal(await generateForDate(date, log), "exists");
      const [row] = await h.q<{ grid_size: number; has_solution: boolean }>(
        `SELECT p.grid_size, EXISTS (SELECT 1 FROM public.puzzle_solutions s WHERE s.puzzle_id = p.id) AS has_solution
           FROM public.puzzles p WHERE p.puzzle_date = $1`,
        [date],
      );
      assert.deepEqual(row, { grid_size: 5, has_solution: true });
    });

    test("rejects dates before launch", async () => {
      await assert.rejects(generateForDate("2025-12-31", new SilentLogger("daily-puzzle", "test")), RangeError);
    });
  });
});

// No database needed: the app-level error contract.
describe("api error handling", () => {
  async function appWith(getSession: () => Promise<unknown>) {
    const { createApp } = await import("../src/index.js");
    const auth = { api: { getSession } } as unknown as import("../src/auth.js").Auth;
    return createApp(() => auth, { logger: (fn, cid) => new SilentLogger(fn, cid) });
  }

  test("an unhandled error is a 500 INTERNAL with the correlation id", async () => {
    const app = await appWith(async () => {
      throw new Error("database unavailable");
    });
    const res = await app.request("http://localhost/api/start-puzzle", {
      method: "POST",
      headers: { "x-correlation-id": "cid-123" },
      body: "{}",
    });
    assert.equal(res.status, 500);
    assert.equal(res.headers.get("x-correlation-id"), "cid-123");
    assert.deepEqual(await res.json(), { error: "Internal server error", code: "INTERNAL" });
  });

  test("requireSession's 401 passes through unchanged", async () => {
    const app = await appWith(async () => null);
    const res = await app.request("http://localhost/api/submit-score", { method: "POST", body: "{}" });
    assert.equal(res.status, 401);
    assert.deepEqual(await res.json(), { error: "Not signed in", code: "UNAUTHORIZED" });
  });
});
