// /api/submit-score over HTTP against the Neon `test` branch: a real puzzle
// generated in-test with the test salt, a session nonce from start-puzzle and
// an HMAC computed exactly as the app does. Skips without NEON_TEST_DATABASE_URL.
import { after, before, describe, test } from "node:test";
import assert from "node:assert/strict";
import { setupApi, SKIP, type ApiHarness } from "./helpers/api.js";
import { addDays, hmacSha256Hex, scoreMessage, sha256Hex, utcToday } from "../src/shared/http.js";
import { generatePuzzle, seedFor, weekdayDifficulty } from "../src/shared/puzzle_core.js";

/** The most recent Monday at least 14 days ago (a 5x5 puzzle inside the 30-day window). */
function recentMonday(): string {
  let d = addDays(utcToday(), -14);
  while (new Date(`${d}T00:00:00Z`).getUTCDay() !== 1) d = addDays(d, -1);
  return d;
}

describe("score routes", { skip: SKIP }, () => {
  let h: ApiHarness;
  const today = utcToday();
  const monday = recentMonday();
  const paths: Record<string, number[][]> = {};

  /** Generates the real puzzle for `date` with the test salt and stores it (upsert). */
  async function storePuzzle(date: string): Promise<void> {
    const { gridSize, difficulty } = weekdayDifficulty(date);
    const generated = generatePuzzle({ size: gridSize, difficulty, seed: seedFor(date, "test-salt") });
    paths[date] = generated.referencePath;
    // Upsert: another test file may have stubbed this date with empty waypoints.
    await h.q(
      `INSERT INTO public.puzzles (puzzle_date, grid_size, waypoints, walls, difficulty, par_time_seconds)
       VALUES ($1, $2, $3::jsonb, $4::jsonb, $5, $6)
       ON CONFLICT (puzzle_date) DO UPDATE
         SET grid_size = EXCLUDED.grid_size, waypoints = EXCLUDED.waypoints, walls = EXCLUDED.walls,
             difficulty = EXCLUDED.difficulty, par_time_seconds = EXCLUDED.par_time_seconds`,
      [
        date,
        generated.gridSize,
        JSON.stringify(generated.waypoints),
        JSON.stringify(generated.walls),
        generated.difficulty,
        generated.parTimeSeconds,
      ],
    );
  }

  before(async () => {
    h = await setupApi();
    assert.equal(weekdayDifficulty(monday).gridSize, 5);
    await storePuzzle(monday);
    await storePuzzle(today);
  });
  after(async () => {
    await h?.close();
  });

  async function started(date: string, who?: { id: string; token: string }) {
    const user = who ?? (await h.signInGuest());
    const { res, json } = await h.call("POST", "/api/start-puzzle", { puzzle_date: date }, user.token);
    assert.equal(res.status, 200, JSON.stringify(json));
    return { ...user, nonce: String(json?.nonce) };
  }

  async function signed(date: string, nonce: string, path: number[][], time = 1, hints = 0, undos = 0) {
    const message = scoreMessage(date, time, hints, undos, await sha256Hex(JSON.stringify(path)));
    return {
      puzzle_date: date,
      time_seconds: time,
      hints_used: hints,
      undos_used: undos,
      path,
      signature: await hmacSha256Hex(nonce, message),
    };
  }

  test("400 BAD_SIGNATURE for a wrong HMAC", async () => {
    const guest = await started(monday);
    const body = await signed(monday, "0".repeat(64), paths[monday]);
    const { res, json } = await h.call("POST", "/api/submit-score", body, guest.token);
    assert.equal(res.status, 400);
    assert.deepEqual(json, { error: "Signature mismatch", code: "BAD_SIGNATURE" });
  });

  test("200 verified live solve: streak 1, rank_hint, feed event; then 409 ALREADY_COMPLETED", async () => {
    const member = await h.signUpEmail("solver");
    const [group] = await h.q<{ id: string }>(
      `INSERT INTO public.groups (name, invite_code, admin_id, member_count)
       VALUES ('Solvers', public.generate_invite_code(), $1, 0) RETURNING id`,
      [member.id],
    );
    await h.q("INSERT INTO public.group_members (group_id, user_id, role) VALUES ($1, $2, 'admin')", [
      group.id,
      member.id,
    ]);
    const player = await started(today, member);
    const body = await signed(today, player.nonce, paths[today]);

    const first = await h.call("POST", "/api/submit-score", body, player.token);
    assert.equal(first.res.status, 200, JSON.stringify(first.json));
    assert.equal(first.json?.completed, true);
    assert.equal(first.json?.verified, true);
    assert.equal(first.json?.is_archive, false);
    assert.deepEqual(first.json?.streak, { current_streak: 1, longest_streak: 1, freeze_count: 1, last_solve_date: today });
    assert.ok(Number.isInteger(first.json?.rank_hint) && first.json?.rank_hint >= 1);

    const [attempt] = await h.q<{ completed: boolean; verified: boolean }>(
      "SELECT completed, verified FROM public.puzzle_attempts WHERE user_id = $1 AND puzzle_date = $2",
      [member.id, today],
    );
    assert.deepEqual(attempt, { completed: true, verified: true });
    const feed = await h.q<{ event: string; payload: Record<string, unknown> }>(
      "SELECT event, payload FROM public.group_feed WHERE group_id = $1 AND user_id = $2",
      [group.id, member.id],
    );
    assert.deepEqual(feed, [
      { event: "solved", payload: { time_seconds: 1, hints_used: 0, undos_used: 0, verified: true } },
    ]);

    const again = await h.call("POST", "/api/submit-score", body, player.token);
    assert.equal(again.res.status, 409);
    assert.deepEqual(again.json, { error: "Puzzle already completed", code: "ALREADY_COMPLETED" });
  });

  test("an archive solve is recorded but neither ranks nor counts for the streak", async () => {
    const guest = await started(monday);
    const { res, json } = await h.call("POST", "/api/submit-score", await signed(monday, guest.nonce, paths[monday]), guest.token);
    assert.equal(res.status, 200, JSON.stringify(json));
    assert.equal(json?.completed, true);
    assert.equal(json?.verified, true);
    assert.equal(json?.is_archive, true);
    assert.equal(json?.streak.current_streak, 0);
    assert.equal("rank_hint" in (json ?? {}), false);
  });

  test("completed:false with reason wrong_length for a short path", async () => {
    const guest = await started(monday);
    const body = await signed(monday, guest.nonce, paths[monday].slice(0, 3));
    const { res, json } = await h.call("POST", "/api/submit-score", body, guest.token);
    assert.equal(res.status, 200);
    assert.deepEqual(json, { completed: false, verified: false, reason: "wrong_length", streak: null });
    const [attempt] = await h.q<{ completed: boolean; attempt_count: number }>(
      "SELECT completed, attempt_count FROM public.puzzle_attempts WHERE user_id = $1 AND puzzle_date = $2",
      [guest.id, monday],
    );
    assert.deepEqual(attempt, { completed: false, attempt_count: 1 });
  });

  test("429 RATE_LIMITED after 40 submissions in an hour", async () => {
    const guest = await started(monday);
    await h.q("INSERT INTO public.submission_log (user_id) SELECT $1 FROM generate_series(1, 40)", [guest.id]);
    const body = await signed(monday, guest.nonce, paths[monday]);
    const { res, json } = await h.call("POST", "/api/submit-score", body, guest.token);
    assert.equal(res.status, 429);
    assert.deepEqual(json, {
      error: "Too many submissions; try again later",
      code: "RATE_LIMITED",
      retry_after_seconds: 3600,
    });
  });

  test("400 INVALID_FIELD names the bad field", async () => {
    const guest = await h.signInGuest();
    const { res, json } = await h.call(
      "POST",
      "/api/submit-score",
      { puzzle_date: monday, time_seconds: 0, path: paths[monday] },
      guest.token,
    );
    assert.equal(res.status, 400);
    assert.deepEqual(json, {
      error: "Invalid or missing field: time_seconds",
      code: "INVALID_FIELD",
      field: "time_seconds",
    });
  });
});
