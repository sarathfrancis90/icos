// submit-score: server-side validation + recording of a solve.
//
// POST {
//   puzzle_date: "YYYY-MM-DD",
//   time_seconds: int (1..86400),
//   hints_used: int (0..100),
//   undos_used: int (0..10000),
//   path: [[row, col], ...],
//   signature?: hex HMAC-SHA256 (key = session nonce) over
//               `${puzzle_date}|${time_seconds}|${hints_used}|${undos_used}|${sha256hex(JSON.stringify(path))}`
//   queued_at?: ISO-8601 (when the solve was recorded offline)
// }
// Auth: user JWT.
//
// 200 { completed: true,  verified, is_archive, streak: {...}, rank_hint? }
// 200 { completed: false, verified: false, reason, streak: null }
// 400 { error, code }  (INVALID_JSON, INVALID_FIELD, DATE_OUT_OF_RANGE, BAD_SIGNATURE,
//                       IMPLAUSIBLE_TIME, CLOCK_SKEW)
// 401 / 403 (BANNED, DELETED)   404 PUZZLE_NOT_FOUND
// 409 { error, code: "ALREADY_COMPLETED" }   429 RATE_LIMITED   500

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  addDays,
  adminClient,
  banCheck,
  compareDates,
  correlationIdFrom,
  CORRELATION_HEADER,
  errorFields,
  errorResponse,
  getUser,
  handleCommon,
  hmacSha256Hex,
  isInt,
  isIsoDate,
  json,
  Logger,
  readJson,
  scoreMessage,
  sha256Hex,
  timingSafeEqual,
  utcToday,
} from "../_shared/http.ts";
import { validatePath } from "../_shared/puzzle_core.ts";

const FN = "submit-score";
const RATE_LIMIT_PER_HOUR = 10;
const DATE_WINDOW_DAYS = 7;
const CLOCK_TOLERANCE_SECONDS = 300;
const MAX_PATH_CELLS = 64; // 8x8

interface PuzzleRow {
  id: string;
  puzzle_date: string;
  grid_size: number;
  waypoints: { order: number; row: number; col: number }[];
  walls: { row: number; col: number }[];
}

interface AttemptRow {
  id: string;
  completed: boolean;
  attempt_count: number;
}

interface StreakRow {
  current_streak: number;
  longest_streak: number;
  freeze_count: number;
  last_solve_date: string | null;
}

Deno.serve(async (req: Request): Promise<Response> => {
  const common = handleCommon(req, FN);
  if (common) return common;

  const correlationId = correlationIdFrom(req);
  const log = new Logger(FN, correlationId);
  const ok = (body: unknown, status = 200) =>
    json(body, status, { [CORRELATION_HEADER]: correlationId });

  if (req.method !== "POST") {
    return errorResponse(405, "Method not allowed", "METHOD_NOT_ALLOWED", correlationId);
  }

  try {
    // ---- auth + ban ---------------------------------------------------------
    const user = await getUser(req);
    if (!user) return errorResponse(401, "Unauthorized", "UNAUTHORIZED", correlationId);
    const admin = adminClient();
    const gate = await banCheck(admin, user.id);
    if (!gate.ok) {
      log.warn("caller rejected", { user_id: user.id, code: gate.code });
      return errorResponse(gate.status, gate.message, gate.code, correlationId);
    }

    // ---- input validation ---------------------------------------------------
    const body = await readJson(req);
    if (body === null) {
      return errorResponse(400, "Body must be a JSON object", "INVALID_JSON", correlationId);
    }
    const bad = (field: string) =>
      errorResponse(400, `Invalid or missing field: ${field}`, "INVALID_FIELD", correlationId, { field });

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
    if (signature !== undefined && signature !== null && !(typeof signature === "string" && /^[0-9a-f]{64}$/i.test(signature))) {
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

    const lg = log.child({ user_id: user.id, puzzle_date: puzzleDate });
    const now = new Date();
    const today = utcToday();

    // ---- date window ---------------------------------------------------------
    if (compareDates(puzzleDate, today) > 0 || compareDates(puzzleDate, addDays(today, -DATE_WINDOW_DAYS)) < 0) {
      lg.warn("date out of range");
      return errorResponse(400, "puzzle_date must be within the last 7 days", "DATE_OUT_OF_RANGE", correlationId);
    }

    // ---- clock plausibility (client clock vs server clock) --------------------
    if (queuedAt && queuedAt.getTime() > now.getTime() + CLOCK_TOLERANCE_SECONDS * 1000) {
      lg.warn("queued_at is in the future", { queued_at: queuedAt.toISOString() });
      return errorResponse(400, "Client clock is ahead of server time", "CLOCK_SKEW", correlationId);
    }

    // ---- rate limit (10 / hour, counted from submission_log) ------------------
    const oneHourAgo = new Date(now.getTime() - 3_600_000).toISOString();
    const { count: recent, error: countError } = await admin
      .from("submission_log")
      .select("id", { count: "exact", head: true })
      .eq("user_id", user.id)
      .gte("created_at", oneHourAgo);
    if (countError) throw new Error(`rate-limit lookup failed: ${countError.message}`);
    if ((recent ?? 0) >= RATE_LIMIT_PER_HOUR) {
      lg.warn("rate limited", { recent });
      return errorResponse(429, "Too many submissions; try again later", "RATE_LIMITED", correlationId, {
        retry_after_seconds: 3600,
      });
    }
    const { error: logError } = await admin.from("submission_log").insert({ user_id: user.id });
    if (logError) throw new Error(`submission_log insert failed: ${logError.message}`);

    // ---- puzzle + existing attempt -------------------------------------------
    const { data: puzzle, error: puzzleError } = await admin
      .from("puzzles")
      .select("id, puzzle_date, grid_size, waypoints, walls")
      .eq("puzzle_date", puzzleDate)
      .maybeSingle();
    if (puzzleError) throw new Error(`puzzle lookup failed: ${puzzleError.message}`);
    if (!puzzle) return errorResponse(404, "Puzzle not found", "PUZZLE_NOT_FOUND", correlationId);
    const p = puzzle as PuzzleRow;

    const { data: existingRaw, error: existingError } = await admin
      .from("puzzle_attempts")
      .select("id, completed, attempt_count")
      .eq("user_id", user.id)
      .eq("puzzle_date", puzzleDate)
      .order("completed", { ascending: false })
      .limit(1)
      .maybeSingle();
    if (existingError) throw new Error(`attempt lookup failed: ${existingError.message}`);
    const existing = existingRaw as AttemptRow | null;
    if (existing?.completed) {
      lg.info("already completed");
      return errorResponse(409, "Puzzle already completed", "ALREADY_COMPLETED", correlationId);
    }

    // ---- path validation -----------------------------------------------------
    const verdict = validatePath(p.grid_size, p.walls, p.waypoints, path);
    if (!verdict.ok) {
      lg.info("invalid path", { reason: verdict.reason });
      await upsertAttempt(admin, existing, {
        user_id: user.id,
        puzzle_id: p.id,
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
      return ok({ completed: false, verified: false, reason: verdict.reason ?? "INVALID_PATH", streak: null });
    }

    // ---- session: HMAC + clock check -----------------------------------------
    const { data: session, error: sessionError } = await admin
      .from("puzzle_sessions")
      .select("nonce, started_at")
      .eq("user_id", user.id)
      .eq("puzzle_date", puzzleDate)
      .maybeSingle();
    if (sessionError) throw new Error(`session lookup failed: ${sessionError.message}`);

    let verified = false;
    if (session) {
      const nonce = session.nonce as string;
      const startedAt = new Date(session.started_at as string);
      const serverElapsed = Math.max(0, (now.getTime() - startedAt.getTime()) / 1000);
      if (timeSeconds > serverElapsed + CLOCK_TOLERANCE_SECONDS) {
        lg.warn("implausible time", { time_seconds: timeSeconds, server_elapsed: Math.round(serverElapsed) });
        return errorResponse(400, "Reported time exceeds elapsed session time", "IMPLAUSIBLE_TIME", correlationId);
      }
      if (typeof signature === "string") {
        const pathHash = await sha256Hex(JSON.stringify(path));
        const expected = await hmacSha256Hex(
          nonce,
          scoreMessage(puzzleDate, timeSeconds, hintsUsed, undosUsed, pathHash),
        );
        if (!timingSafeEqual(expected, signature.toLowerCase())) {
          lg.warn("bad signature");
          return errorResponse(400, "Signature mismatch", "BAD_SIGNATURE", correlationId);
        }
        verified = true;
      } else {
        lg.info("no signature supplied; accepting unverified");
      }
    } else {
      lg.info("no session for this date; accepting unverified");
    }

    // ---- archive determination ------------------------------------------------
    // completed_at = queued_at when the solve was recorded offline (and is plausible),
    // otherwise now. A solve is "live" only if it finished before the puzzle's UTC day ended.
    const puzzleDayStart = new Date(`${puzzleDate}T00:00:00Z`).getTime();
    let completedAt = now;
    if (queuedAt && queuedAt.getTime() >= puzzleDayStart && queuedAt.getTime() <= now.getTime()) {
      completedAt = queuedAt;
    }
    const isArchive = completedAt.getTime() - puzzleDayStart > 86_400_000;

    // ---- persist attempt -------------------------------------------------------
    const stored = await upsertAttempt(admin, existing, {
      user_id: user.id,
      puzzle_id: p.id,
      puzzle_date: puzzleDate,
      time_seconds: timeSeconds,
      hints_used: hintsUsed,
      undos_used: undosUsed,
      completed: true,
      verified,
      is_archive: isArchive,
      path,
      completed_at: completedAt.toISOString(),
    });
    if (stored === "conflict") {
      lg.info("concurrent completion detected");
      return errorResponse(409, "Puzzle already completed", "ALREADY_COMPLETED", correlationId);
    }

    // ---- streak ---------------------------------------------------------------
    const { data: streakRaw, error: streakError } = await admin.rpc("record_solve", {
      p_user_id: user.id,
      p_puzzle_date: puzzleDate,
    });
    if (streakError) throw new Error(`record_solve failed: ${streakError.message}`);
    const streakRow = (Array.isArray(streakRaw) ? streakRaw[0] : streakRaw) as StreakRow | null;
    const streak = streakRow
      ? {
        current_streak: streakRow.current_streak,
        longest_streak: streakRow.longest_streak,
        freeze_count: streakRow.freeze_count,
        last_solve_date: streakRow.last_solve_date,
      }
      : null;

    // ---- group feed -------------------------------------------------------------
    const { data: memberships } = await admin
      .from("group_members")
      .select("group_id, groups!inner(is_active)")
      .eq("user_id", user.id)
      .eq("groups.is_active", true);
    const groupIds = (memberships ?? []).map((m) => (m as { group_id: string }).group_id);
    if (groupIds.length > 0) {
      const { error: feedError } = await admin.from("group_feed").insert(
        groupIds.map((group_id) => ({
          group_id,
          user_id: user.id,
          puzzle_date: puzzleDate,
          event: isArchive ? "solved_archive" : "solved",
          payload: { time_seconds: timeSeconds, hints_used: hintsUsed, undos_used: undosUsed, verified },
        })),
      );
      if (feedError) lg.warn("group_feed insert failed", { db_error: feedError.message });
    }

    // ---- rank hint (global, live solves only) -----------------------------------
    let rankHint: number | undefined;
    if (!isArchive) {
      const { count } = await admin
        .from("puzzle_attempts")
        .select("id", { count: "exact", head: true })
        .eq("puzzle_date", puzzleDate)
        .eq("completed", true)
        .eq("is_archive", false)
        .or(
          `hints_used.lt.${hintsUsed},` +
            `and(hints_used.eq.${hintsUsed},time_seconds.lt.${timeSeconds}),` +
            `and(hints_used.eq.${hintsUsed},time_seconds.eq.${timeSeconds},undos_used.lt.${undosUsed})`,
        );
      rankHint = (count ?? 0) + 1;
    }

    lg.info("solve recorded", {
      verified,
      is_archive: isArchive,
      time_seconds: timeSeconds,
      hints_used: hintsUsed,
      undos_used: undosUsed,
      current_streak: streak?.current_streak,
      rank_hint: rankHint,
      groups_notified: groupIds.length,
    });

    return ok({
      completed: true,
      verified,
      is_archive: isArchive,
      streak,
      ...(rankHint !== undefined ? { rank_hint: rankHint } : {}),
    });
  } catch (err) {
    log.error("unhandled error", errorFields(err));
    return errorResponse(500, "Internal server error", "INTERNAL", correlationId);
  }
});

function isPath(v: unknown): v is number[][] {
  if (!Array.isArray(v) || v.length === 0 || v.length > MAX_PATH_CELLS) return false;
  return v.every((cell) =>
    Array.isArray(cell) && cell.length === 2 &&
    Number.isInteger(cell[0]) && Number.isInteger(cell[1]) &&
    cell[0] >= 0 && cell[0] < 8 && cell[1] >= 0 && cell[1] < 8
  );
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
  completed_at: string | null;
}

/**
 * Update the caller's existing (incomplete) attempt row or insert a new one.
 * Returns "conflict" if the partial unique index rejects a second completed row.
 */
async function upsertAttempt(
  admin: SupabaseClient,
  existing: AttemptRow | null,
  row: AttemptWrite,
): Promise<"ok" | "conflict"> {
  if (existing) {
    const { error } = await admin
      .from("puzzle_attempts")
      .update({ ...row, attempt_count: existing.attempt_count + 1 })
      .eq("id", existing.id);
    if (error) {
      if (error.code === "23505") return "conflict";
      throw new Error(`attempt update failed: ${error.message}`);
    }
    return "ok";
  }
  const { error } = await admin.from("puzzle_attempts").insert({ ...row, attempt_count: 1 });
  if (error) {
    if (error.code === "23505") return "conflict";
    throw new Error(`attempt insert failed: ${error.message}`);
  }
  return "ok";
}
