// POST /api/submit-score: server-side validation and recording of a solve
// (port of the submit-score edge function; same request and responses).
//
// { puzzle_date, time_seconds (1..86400), hints_used (0..100), undos_used (0..10000),
//   path: [[row, col], ...], signature?: hex HMAC-SHA256(key = session nonce) over
//   `${puzzle_date}|${time_seconds}|${hints_used}|${undos_used}|${sha256hex(JSON.stringify(path))}`,
//   queued_at?: ISO-8601 }
//
// 200 { completed: true,  verified, is_archive, streak: {...}, rank_hint? }
// 200 { completed: false, verified: false, reason, streak: null }
// 400 INVALID_JSON / INVALID_FIELD / DATE_OUT_OF_RANGE / BAD_SIGNATURE / IMPLAUSIBLE_TIME / CLOCK_SKEW
// 401 / 403 (BANNED, DELETED)   404 PUZZLE_NOT_FOUND   409 ALREADY_COMPLETED   429 RATE_LIMITED
import { Hono } from "hono";
import { q } from "../db.js";
import {
  ARCHIVE_WINDOW_DAYS,
  hmacSha256Hex,
  isInt,
  isIsoDate,
  isWithinArchiveWindow,
  readJson,
  scoreMessage,
  sha256Hex,
  timingSafeEqual,
  utcToday,
} from "../shared/http.js";
import { validatePath, type Cell, type Waypoint } from "../shared/puzzle_core.js";
import { activeUser, type ApiDeps, methodNotAllowed, pgError, requestCtx } from "./common.js";

const RATE_LIMIT_PER_HOUR = 40;
const CLOCK_TOLERANCE_SECONDS = 300;
const MAX_PATH_CELLS = 64; // 8x8

interface PuzzleRow {
  id: string;
  grid_size: number;
  waypoints: Waypoint[];
  walls: Cell[];
}

interface AttemptRow {
  id: string;
  completed: boolean;
  attempt_count: number;
}

interface StreakRow {
  current_streak: number | null;
  longest_streak: number;
  freeze_count: number;
  last_solve_date: string | null;
}

interface AttemptWrite {
  user_id: string;
  puzzle_id: string;
  puzzle_date: string;
  time_seconds: number;
  hints_used: number;
  undos_used: number;
  completed: boolean;
  verified: boolean;
  is_archive: boolean;
  path: number[][];
  completed_at: Date | null;
}

function isPath(v: unknown): v is number[][] {
  if (!Array.isArray(v) || v.length === 0 || v.length > MAX_PATH_CELLS) return false;
  return v.every(
    (cell) =>
      Array.isArray(cell) &&
      cell.length === 2 &&
      Number.isInteger(cell[0]) &&
      Number.isInteger(cell[1]) &&
      cell[0] >= 0 &&
      cell[0] < 8 &&
      cell[1] >= 0 &&
      cell[1] < 8,
  );
}

/**
 * Updates the caller's existing (incomplete) attempt or inserts a new one.
 * "conflict" when the one-completed-per-day unique index rejects the write.
 */
async function upsertAttempt(existing: AttemptRow | null, row: AttemptWrite): Promise<"ok" | "conflict"> {
  const values = [
    row.user_id,
    row.puzzle_id,
    row.puzzle_date,
    row.time_seconds,
    row.hints_used,
    row.undos_used,
    row.completed,
    row.verified,
    row.is_archive,
    JSON.stringify(row.path),
    row.completed_at,
  ];
  try {
    if (existing) {
      await q(
        `UPDATE public.puzzle_attempts
            SET user_id = $1, puzzle_id = $2, puzzle_date = $3, time_seconds = $4, hints_used = $5,
                undos_used = $6, completed = $7, verified = $8, is_archive = $9, path = $10::jsonb,
                completed_at = $11, attempt_count = $12, updated_at = now()
          WHERE id = $13`,
        [...values, existing.attempt_count + 1, existing.id],
      );
    } else {
      await q(
        `INSERT INTO public.puzzle_attempts
           (user_id, puzzle_id, puzzle_date, time_seconds, hints_used, undos_used, completed, verified,
            is_archive, path, completed_at, attempt_count)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10::jsonb, $11, 1)`,
        values,
      );
    }
    return "ok";
  } catch (err) {
    if (pgError(err).code === "23505") return "conflict";
    throw err;
  }
}

export function scoreRoutes(deps: ApiDeps): Hono {
  const app = new Hono();

  app.all("/submit-score", async (c) => {
    const r = requestCtx(c, deps, "submit-score");
    if (c.req.method !== "POST") return methodNotAllowed(r);

    // ---- auth + ban ---------------------------------------------------------
    const gate = await activeUser(c, deps, r);
    if (gate instanceof Response) return gate;
    const { user } = gate;

    // ---- input validation ---------------------------------------------------
    const body = await readJson(c.req.raw);
    if (body === null) return r.fail(400, "Body must be a JSON object", "INVALID_JSON");
    const bad = (field: string) => r.fail(400, `Invalid or missing field: ${field}`, "INVALID_FIELD", { field });

    const puzzleDate = body.puzzle_date;
    if (!isIsoDate(puzzleDate)) return bad("puzzle_date");
    const timeSeconds = body.time_seconds;
    if (!isInt(timeSeconds, 1, 86_400)) return bad("time_seconds");
    const hintsUsed = body.hints_used ?? 0;
    if (!isInt(hintsUsed, 0, 100)) return bad("hints_used");
    const undosUsed = body.undos_used ?? 0;
    if (!isInt(undosUsed, 0, 10_000)) return bad("undos_used");
    const path = body.path;
    if (!isPath(path)) return bad("path");
    const signature = body.signature;
    if (
      signature !== undefined &&
      signature !== null &&
      !(typeof signature === "string" && /^[0-9a-f]{64}$/i.test(signature))
    ) {
      return bad("signature");
    }
    const queuedAtRaw = body.queued_at;
    let queuedAt: Date | null = null;
    if (queuedAtRaw !== undefined && queuedAtRaw !== null) {
      if (typeof queuedAtRaw !== "string") return bad("queued_at");
      const d = new Date(queuedAtRaw);
      if (Number.isNaN(d.getTime())) return bad("queued_at");
      queuedAt = d;
    }

    const lg = r.log.child({ user_id: user.id, puzzle_date: puzzleDate });
    const now = new Date();

    // ---- date window ---------------------------------------------------------
    if (!isWithinArchiveWindow(puzzleDate, utcToday())) {
      lg.warn("date out of range");
      return r.fail(400, `puzzle_date must be within the last ${ARCHIVE_WINDOW_DAYS} days`, "DATE_OUT_OF_RANGE");
    }

    // ---- clock plausibility (client clock vs server clock) --------------------
    if (queuedAt && queuedAt.getTime() > now.getTime() + CLOCK_TOLERANCE_SECONDS * 1000) {
      lg.warn("queued_at is in the future", { queued_at: queuedAt.toISOString() });
      return r.fail(400, "Client clock is ahead of server time", "CLOCK_SKEW");
    }

    // ---- rate limit (40 / hour, counted from submission_log) ------------------
    const [{ recent }] = await q<{ recent: number }>(
      "SELECT count(*)::int AS recent FROM public.submission_log WHERE user_id = $1 AND created_at >= $2",
      [user.id, new Date(now.getTime() - 3_600_000)],
    );
    if (recent >= RATE_LIMIT_PER_HOUR) {
      lg.warn("rate limited", { recent });
      return r.fail(429, "Too many submissions; try again later", "RATE_LIMITED", { retry_after_seconds: 3600 });
    }
    await q("INSERT INTO public.submission_log (user_id) VALUES ($1)", [user.id]);

    // ---- puzzle + existing attempt -------------------------------------------
    const [puzzle] = await q<PuzzleRow>(
      "SELECT id, grid_size, waypoints, walls FROM public.puzzles WHERE puzzle_date = $1 LIMIT 1",
      [puzzleDate],
    );
    if (!puzzle) return r.fail(404, "Puzzle not found", "PUZZLE_NOT_FOUND");

    const [existingRow] = await q<AttemptRow>(
      `SELECT id, completed, attempt_count FROM public.puzzle_attempts
        WHERE user_id = $1 AND puzzle_date = $2
        ORDER BY completed DESC LIMIT 1`,
      [user.id, puzzleDate],
    );
    const existing = existingRow ?? null;
    if (existing?.completed) {
      lg.info("already completed");
      return r.fail(409, "Puzzle already completed", "ALREADY_COMPLETED");
    }

    // ---- path validation -----------------------------------------------------
    const verdict = validatePath(puzzle.grid_size, puzzle.walls, puzzle.waypoints, path);
    if (!verdict.ok) {
      lg.info("invalid path", { reason: verdict.reason });
      await upsertAttempt(existing, {
        user_id: user.id,
        puzzle_id: puzzle.id,
        puzzle_date: puzzleDate,
        time_seconds: timeSeconds,
        hints_used: hintsUsed,
        undos_used: undosUsed,
        completed: false,
        verified: false,
        is_archive: false,
        path,
        completed_at: null,
      });
      return r.ok({ completed: false, verified: false, reason: verdict.reason ?? "INVALID_PATH", streak: null });
    }

    // ---- session: HMAC + clock check -----------------------------------------
    const [session] = await q<{ nonce: string; started_at: Date }>(
      "SELECT nonce, started_at FROM public.puzzle_sessions WHERE user_id = $1 AND puzzle_date = $2 LIMIT 1",
      [user.id, puzzleDate],
    );

    let verified = false;
    if (session) {
      const serverElapsed = Math.max(0, (now.getTime() - new Date(session.started_at).getTime()) / 1000);
      if (timeSeconds > serverElapsed + CLOCK_TOLERANCE_SECONDS) {
        lg.warn("implausible time", { time_seconds: timeSeconds, server_elapsed: Math.round(serverElapsed) });
        return r.fail(400, "Reported time exceeds elapsed session time", "IMPLAUSIBLE_TIME");
      }
      if (typeof signature === "string") {
        const pathHash = await sha256Hex(JSON.stringify(path));
        const expected = await hmacSha256Hex(
          session.nonce,
          scoreMessage(puzzleDate, timeSeconds, hintsUsed, undosUsed, pathHash),
        );
        if (!timingSafeEqual(expected, signature.toLowerCase())) {
          lg.warn("bad signature");
          return r.fail(400, "Signature mismatch", "BAD_SIGNATURE");
        }
        verified = true;
      } else {
        lg.info("no signature supplied; accepting unverified");
      }
    } else {
      lg.info("no session for this date; accepting unverified");
    }

    // ---- archive determination ------------------------------------------------
    // completed_at = queued_at when the solve was recorded offline (and is
    // plausible), otherwise now. A solve is "live" only if it finished before
    // the puzzle's UTC day ended.
    const puzzleDayStart = new Date(`${puzzleDate}T00:00:00Z`).getTime();
    let completedAt = now;
    if (queuedAt && queuedAt.getTime() >= puzzleDayStart && queuedAt.getTime() <= now.getTime()) {
      completedAt = queuedAt;
    }
    const isArchive = completedAt.getTime() - puzzleDayStart > 86_400_000;

    // ---- persist attempt -------------------------------------------------------
    const stored = await upsertAttempt(existing, {
      user_id: user.id,
      puzzle_id: puzzle.id,
      puzzle_date: puzzleDate,
      time_seconds: timeSeconds,
      hints_used: hintsUsed,
      undos_used: undosUsed,
      completed: true,
      verified,
      is_archive: isArchive,
      path,
      completed_at: completedAt,
    });
    if (stored === "conflict") {
      lg.info("concurrent completion detected");
      return r.fail(409, "Puzzle already completed", "ALREADY_COMPLETED");
    }

    // ---- streak ---------------------------------------------------------------
    const [streakRow] = await q<StreakRow>(
      "SELECT current_streak, longest_streak, freeze_count, last_solve_date FROM public.record_solve($1, $2)",
      [user.id, puzzleDate],
    );
    const streak =
      streakRow && streakRow.current_streak !== null
        ? {
            current_streak: streakRow.current_streak,
            longest_streak: streakRow.longest_streak,
            freeze_count: streakRow.freeze_count,
            last_solve_date: streakRow.last_solve_date,
          }
        : null;

    // ---- group feed (every active group the solver belongs to) ------------------
    let groupsNotified = 0;
    try {
      const fed = await q(
        `INSERT INTO public.group_feed (group_id, user_id, puzzle_date, event, payload)
         SELECT gm.group_id, $1, $2, $3, $4::jsonb
           FROM public.group_members gm
           JOIN public.groups g ON g.id = gm.group_id AND g.is_active
          WHERE gm.user_id = $1
         RETURNING id`,
        [
          user.id,
          puzzleDate,
          isArchive ? "solved_archive" : "solved",
          JSON.stringify({ time_seconds: timeSeconds, hints_used: hintsUsed, undos_used: undosUsed, verified }),
        ],
      );
      groupsNotified = fed.length;
    } catch (err) {
      lg.warn("group_feed insert failed", { db_error: err instanceof Error ? err.message : String(err) });
    }

    // ---- rank hint (global, live solves only) -----------------------------------
    let rankHint: number | undefined;
    if (!isArchive) {
      let ahead = 0;
      try {
        const [row] = await q<{ ahead: number }>(
          `SELECT count(*)::int AS ahead FROM public.puzzle_attempts
            WHERE puzzle_date = $1 AND completed AND NOT is_archive
              AND (hints_used < $2
                   OR (hints_used = $2 AND time_seconds < $3)
                   OR (hints_used = $2 AND time_seconds = $3 AND undos_used < $4))`,
          [puzzleDate, hintsUsed, timeSeconds, undosUsed],
        );
        ahead = row.ahead;
      } catch (err) {
        lg.warn("rank hint lookup failed", { db_error: err instanceof Error ? err.message : String(err) });
      }
      rankHint = ahead + 1;
    }

    lg.info("solve recorded", {
      verified,
      is_archive: isArchive,
      time_seconds: timeSeconds,
      hints_used: hintsUsed,
      undos_used: undosUsed,
      current_streak: streak?.current_streak,
      rank_hint: rankHint,
      groups_notified: groupsNotified,
    });

    return r.ok({
      completed: true,
      verified,
      is_archive: isArchive,
      streak,
      ...(rankHint !== undefined ? { rank_hint: rankHint } : {}),
    });
  });

  return app;
}
