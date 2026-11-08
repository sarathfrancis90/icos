// POST /cron/:job (the Neon schedule triggers) against the Neon `test` branch.
// Skips without NEON_TEST_DATABASE_URL.
//
// Puzzle dates owned by this file:
//   - 2026-02-02 (Mon, 5x5) and 2026-02-03 (Tue, 5x5): deleted, then generated
//   - 2026-02-04 (Wed): stub puzzle (the "existing" date)
//   - 2030-01-07 … 2030-01-21: never written (a fake generator records calls)
import { after, before, describe, test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import type { Hono } from "hono";
import { setupApi, SilentLogger, SKIP, type ApiHarness, type Json } from "./helpers/api.js";
import type { CronOptions } from "../src/routes/cron.js";

const INVOCATION_HEADER = "X-Neon-Trigger-Invocation-Id";

describe("cron routes", { skip: SKIP }, () => {
  let h: ApiHarness;
  let createApp: typeof import("../src/index.js").createApp;
  let app: Hono;

  before(async () => {
    h = await setupApi();
    ({ createApp } = await import("../src/index.js"));
    app = build();
  });
  after(async () => {
    await h?.close();
  });

  function build(cron: CronOptions = {}): Hono {
    return createApp(() => h.auth, { logger: (fn, cid) => new SilentLogger(fn, cid), cron });
  }

  /** A unique schedule time near now (old rows are pruned by ran_at, not this). */
  function scheduledAt(): string {
    return new Date(Date.now() - Math.floor(Math.random() * 86_400_000)).toISOString();
  }

  function payload(job: string, at: string = scheduledAt()) {
    const invocationId = randomUUID();
    return {
      invocationId,
      body: {
        version: 1,
        invocation_id: invocationId,
        trigger: { type: "schedule", id: randomUUID(), name: job.replaceAll("-", "") },
        data: { scheduled_at: at },
        previous_attempts: 0,
      },
    };
  }

  async function cron(
    job: string,
    opts: { app?: Hono; at?: string; header?: boolean } = {},
  ): Promise<{ res: Response; json: Json | null; at: string }> {
    const at = opts.at ?? scheduledAt();
    const { invocationId, body } = payload(job, at);
    const headers: Record<string, string> = { "content-type": "application/json" };
    if (opts.header !== false) headers[INVOCATION_HEADER] = invocationId;
    const res = await (opts.app ?? app).request(`http://localhost/cron/${job}`, {
      method: "POST",
      headers,
      body: JSON.stringify(body),
    });
    const text = await res.text();
    return { res, json: text ? (JSON.parse(text) as Json) : null, at };
  }

  async function authUserExists(id: string): Promise<boolean> {
    const rows = await h.q(`SELECT 1 FROM ba."user" WHERE id = $1`, [id]);
    return rows.length === 1;
  }

  async function cronRunExists(job: string, at: string): Promise<boolean> {
    const rows = await h.q(`SELECT 1 FROM public.cron_runs WHERE job = $1 AND scheduled_at = $2`, [job, at]);
    return rows.length === 1;
  }

  test("401 without the Neon invocation header", async () => {
    const { res, json } = await cron("prune-submission-log", { header: false });
    assert.equal(res.status, 401);
    assert.deepEqual(json, { error: "Unauthorized", code: "UNAUTHORIZED" });
  });

  test("404 UNKNOWN_JOB for a job that does not exist", async () => {
    const { res, json } = await cron("drop-everything");
    assert.equal(res.status, 404);
    assert.equal(json?.code, "UNKNOWN_JOB");
  });

  test("a duplicate delivery of the same scheduled_at does not run again", async () => {
    const first = await cron("prune-submission-log");
    assert.equal(first.res.status, 200, JSON.stringify(first.json));
    assert.equal(first.json?.job, "prune-submission-log");
    assert.equal(first.json?.ran, true);
    assert.equal(typeof first.json?.result.count, "number");

    const second = await cron("prune-submission-log", { at: first.at });
    assert.equal(second.res.status, 200);
    assert.deepEqual(second.json, { job: "prune-submission-log", ran: false });
  });

  test("the SQL jobs run and report their counts", async () => {
    for (const job of ["reset-weekly-freezes", "apply-streak-freezes", "expire-stale-streaks"]) {
      const { res, json } = await cron(job);
      assert.equal(res.status, 200, `${job}: ${JSON.stringify(json)}`);
      assert.equal(json?.ran, true);
      assert.equal(typeof json?.result.count, "number", job);
    }
  });

  test("daily-puzzle generates the missing dates of its window and skips existing ones", async () => {
    const [mon, tue, wed] = ["2026-02-02", "2026-02-03", "2026-02-04"];
    await h.q("DELETE FROM public.puzzles WHERE puzzle_date = ANY($1::date[])", [[mon, tue]]);
    await h.q(
      `INSERT INTO public.puzzles (puzzle_date, grid_size, waypoints, difficulty, par_time_seconds)
       VALUES ($1, 6, '[]'::jsonb, 'medium', 60) ON CONFLICT (puzzle_date) DO NOTHING`,
      [wed],
    );
    const windowed = build({ today: () => mon, windowDays: 2 });

    const { res, json } = await cron("daily-puzzle", { app: windowed });
    assert.equal(res.status, 200, JSON.stringify(json));
    assert.deepEqual(json?.result, { created: [mon, tue], existing: 1 });

    const rows = await h.q<{ puzzle_date: string; grid_size: number }>(
      `SELECT puzzle_date, grid_size FROM public.puzzles WHERE puzzle_date = ANY($1::date[]) ORDER BY puzzle_date`,
      [[mon, tue]],
    );
    assert.deepEqual(rows, [
      { puzzle_date: mon, grid_size: 5 },
      { puzzle_date: tue, grid_size: 5 },
    ]);
  });

  test("daily-puzzle covers today … today+14 by default", async () => {
    const calls: string[] = [];
    const fake = build({
      today: () => "2030-01-07",
      generateForDate: async (date) => {
        calls.push(date);
        return "created";
      },
    });
    const { res, json } = await cron("daily-puzzle", { app: fake });
    assert.equal(res.status, 200, JSON.stringify(json));
    assert.equal(calls.length, 15);
    assert.equal(calls[0], "2030-01-07");
    assert.equal(calls[14], "2030-01-21");
    assert.deepEqual(json?.result, { created: calls, existing: 0 });
  });

  test("daily-puzzle keeps going past a failed date, then fails the run so Neon retries", async () => {
    const calls: string[] = [];
    const flaky = build({
      today: () => "2030-01-07",
      windowDays: 2,
      generateForDate: async (date) => {
        calls.push(date);
        if (date === "2030-01-08") throw new Error("generator budget exhausted");
        return "created";
      },
    });
    const { res, json, at } = await cron("daily-puzzle", { app: flaky });
    assert.equal(res.status, 503, JSON.stringify(json));
    assert.equal(res.headers.get("retry-after"), "300");
    assert.equal(json?.code, "JOB_FAILED");
    assert.deepEqual(calls, ["2030-01-07", "2030-01-08", "2030-01-09"]);
    assert.deepEqual(json?.result, { created: ["2030-01-07", "2030-01-09"], existing: 0, failed: ["2030-01-08"] });
    assert.equal(await cronRunExists("daily-puzzle", at), false, "the retry may run it again");
  });

  test("a failing job answers 503 + Retry-After and frees its cron_runs slot", async () => {
    const broken = build({
      jobs: {
        "reset-weekly-freezes": async () => {
          throw new Error("boom");
        },
      },
    });
    const { res, json, at } = await cron("reset-weekly-freezes", { app: broken });
    assert.equal(res.status, 503);
    assert.equal(res.headers.get("retry-after"), "300");
    assert.equal(json?.code, "JOB_FAILED");
    assert.equal(await cronRunExists("reset-weekly-freezes", at), false);

    // Neon's retry of the same scheduled_at then runs normally.
    const retry = await cron("reset-weekly-freezes", { at });
    assert.equal(retry.res.status, 200);
    assert.equal(retry.json?.ran, true);
  });

  test("purge-deleted-accounts removes the auth user of a profile past its grace period", async () => {
    const user = await h.signInGuest();
    await h.q(
      `UPDATE public.profiles SET deleted_at = now() - interval '31 days', is_anonymous = false WHERE id = $1`,
      [user.id],
    );
    const { res, json } = await cron("purge-deleted-accounts");
    assert.equal(res.status, 200, JSON.stringify(json));
    assert.ok(json?.result.purged >= 1, JSON.stringify(json));
    assert.equal(typeof json?.result.healed, "number");

    assert.equal(await authUserExists(user.id), false);
    const sessions = await h.q(`SELECT 1 FROM ba."session" WHERE "userId" = $1`, [user.id]);
    assert.equal(sessions.length, 0, "sessions cascade with the auth user");
    const [profile] = await h.q<{ display_name: string; purged: boolean }>(
      `SELECT display_name, purged_at IS NOT NULL AS purged FROM public.profiles WHERE id = $1`,
      [user.id],
    );
    assert.deepEqual(profile, { display_name: "Deleted User", purged: true }, "the profile stays, anonymized");
  });

  test("purge-deleted-accounts heals an auth user left behind by an earlier purge", async () => {
    const user = await h.signInGuest();
    await h.q(`UPDATE public.profiles SET is_anonymous = false, purged_at = now() WHERE id = $1`, [user.id]);
    const { res, json } = await cron("purge-deleted-accounts");
    assert.equal(res.status, 200, JSON.stringify(json));
    assert.ok(json?.result.healed >= 1, JSON.stringify(json));
    assert.equal(await authUserExists(user.id), false);
  });

  test("purge-inactive-anonymous removes an idle guest's auth user, profile and attempts", async () => {
    const guest = await h.signInGuest();
    const keep = await h.signInGuest();
    const [puzzle] = await h.q<{ id: string }>(
      `INSERT INTO public.puzzles (puzzle_date, grid_size, waypoints, difficulty, par_time_seconds)
       VALUES ('2026-02-04', 6, '[]'::jsonb, 'medium', 60)
       ON CONFLICT (puzzle_date) DO UPDATE SET puzzle_date = EXCLUDED.puzzle_date RETURNING id`,
    );
    await h.q(
      `INSERT INTO public.puzzle_attempts (user_id, puzzle_id, puzzle_date, time_seconds, completed)
       VALUES ($1, $2, '2026-02-04', 42, true)`,
      [guest.id, puzzle.id],
    );
    await h.q(`UPDATE public.profiles SET last_active_at = now() - interval '91 days' WHERE id = $1`, [guest.id]);

    const { res, json } = await cron("purge-inactive-anonymous");
    assert.equal(res.status, 200, JSON.stringify(json));
    assert.ok(json?.result.purged >= 1, JSON.stringify(json));
    assert.equal(typeof json?.result.healed, "number");

    assert.equal(await authUserExists(guest.id), false);
    assert.equal((await h.q(`SELECT 1 FROM public.profiles WHERE id = $1`, [guest.id])).length, 0);
    assert.equal((await h.q(`SELECT 1 FROM public.puzzle_attempts WHERE user_id = $1`, [guest.id])).length, 0);
    assert.equal(await authUserExists(keep.id), true, "an active guest stays");
  });

  test("purge-inactive-anonymous heals a guest auth user whose profile is gone", async () => {
    const orphan = await h.signInGuest();
    const fresh = await h.signInGuest();
    await h.q(`DELETE FROM public.profiles WHERE id = ANY($1::uuid[])`, [[orphan.id, fresh.id]]);
    await h.q(`UPDATE ba."user" SET "createdAt" = now() - interval '2 hours' WHERE id = $1`, [orphan.id]);

    const { res, json } = await cron("purge-inactive-anonymous");
    assert.equal(res.status, 200, JSON.stringify(json));
    assert.ok(json?.result.healed >= 1, JSON.stringify(json));
    assert.equal(await authUserExists(orphan.id), false);
    assert.equal(await authUserExists(fresh.id), true, "a guest created moments ago is left for the auth hooks");
    await h.q(`DELETE FROM ba."user" WHERE id = $1`, [fresh.id]);
  });
});
