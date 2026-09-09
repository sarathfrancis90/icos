// daily-puzzle: generate (or return) the deterministic puzzle for a date.
//
// POST { date?: "YYYY-MM-DD" }   (default: tomorrow UTC)
// Auth: Authorization bearer == SUPABASE_SERVICE_ROLE_KEY (cron/backfill, any date)
//       OR a valid user JWT (today or tomorrow UTC only).
// Idempotent: if the puzzle already exists it is returned with status "exists".
//
// 200 { status: "exists",  puzzle_date, puzzle }
// 201 { status: "created", puzzle_date, puzzle }
// 400 { error, code }  401/403  500 { error, code }
//
// The reference solution is stored in puzzle_solutions (service-role only) and is
// NEVER included in the response.

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
  isIsoDate,
  json,
  Logger,
  readJson,
  requireServiceRole,
  utcToday,
} from "../_shared/http.ts";
import { generatePuzzle, seedFor, weekdayDifficulty } from "../_shared/puzzle_core.ts";

const FN = "daily-puzzle";
const NODE_BUDGET = 2_000_000;

interface PublicPuzzleRow {
  id: string;
  puzzle_date: string;
  grid_size: number;
  waypoints: unknown;
  walls: unknown;
  difficulty: string;
  par_time_seconds: number;
  difficulty_score: number | null;
  seed_version: number;
  created_at: string;
}

const PUBLIC_COLUMNS =
  "id, puzzle_date, grid_size, waypoints, walls, difficulty, par_time_seconds, difficulty_score, seed_version, created_at";

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
    const salt = Deno.env.get("PUZZLE_SEED_SALT");
    if (!salt) {
      log.error("PUZZLE_SEED_SALT is not configured; refusing to generate");
      return errorResponse(500, "Server misconfigured", "MISSING_SEED_SALT", correlationId);
    }

    const admin = adminClient();

    // ---- auth ---------------------------------------------------------------
    const isService = requireServiceRole(req);
    let userId: string | null = null;
    if (!isService) {
      const user = await getUser(req);
      if (!user) {
        return errorResponse(401, "Unauthorized", "UNAUTHORIZED", correlationId);
      }
      const gate = await banCheck(admin, user.id);
      if (!gate.ok) {
        log.warn("caller rejected", { user_id: user.id, code: gate.code });
        return errorResponse(gate.status, gate.message, gate.code, correlationId);
      }
      userId = user.id;
    }

    // ---- input --------------------------------------------------------------
    const body = await readJson(req);
    if (body === null) {
      return errorResponse(400, "Body must be a JSON object", "INVALID_JSON", correlationId);
    }
    const today = utcToday();
    const tomorrow = addDays(today, 1);
    const date = body.date === undefined || body.date === null ? tomorrow : body.date;
    if (!isIsoDate(date)) {
      return errorResponse(400, "date must be YYYY-MM-DD", "INVALID_DATE", correlationId);
    }
    if (!isService && date !== today && date !== tomorrow) {
      log.warn("user requested out-of-window date", { user_id: userId, date });
      return errorResponse(
        403,
        "Only today's or tomorrow's puzzle can be requested",
        "DATE_NOT_ALLOWED",
        correlationId,
      );
    }
    if (isService && compareDates(date, "2026-01-01") < 0) {
      return errorResponse(400, "date is before launch", "INVALID_DATE", correlationId);
    }

    const lg = log.child({ date, caller: isService ? "service_role" : "user", user_id: userId });

    // ---- idempotency --------------------------------------------------------
    const existing = await fetchPublic(admin, date);
    if (existing) {
      lg.info("puzzle already exists");
      return ok({ status: "exists", puzzle_date: date, puzzle: existing }, 200);
    }

    // ---- generate -----------------------------------------------------------
    const { gridSize, difficulty } = weekdayDifficulty(date);
    const seed = seedFor(date, salt);
    const t0 = performance.now();
    const generated = generatePuzzle({ size: gridSize, difficulty, seed, nodeBudget: NODE_BUDGET });
    const genMs = Math.round(performance.now() - t0);
    lg.info("puzzle generated", {
      grid_size: generated.gridSize,
      difficulty: generated.difficulty,
      walls: generated.walls.length,
      waypoints: generated.waypoints.length,
      difficulty_score: generated.difficultyScore,
      gen_ms: genMs,
    });

    const { data: inserted, error: insertError } = await admin
      .from("puzzles")
      .insert({
        puzzle_date: date,
        grid_size: generated.gridSize,
        waypoints: generated.waypoints,
        walls: generated.walls,
        difficulty: generated.difficulty,
        par_time_seconds: generated.parTimeSeconds,
        difficulty_score: generated.difficultyScore,
        seed_version: 2,
      })
      .select(PUBLIC_COLUMNS)
      .single();

    if (insertError) {
      // 23505 = unique_violation: a concurrent call won the race; return theirs.
      if (insertError.code === "23505") {
        const winner = await fetchPublic(admin, date);
        if (winner) {
          lg.info("lost insert race; returning existing puzzle");
          return ok({ status: "exists", puzzle_date: date, puzzle: winner }, 200);
        }
      }
      lg.error("puzzle insert failed", { db_error: insertError.message, db_code: insertError.code });
      return errorResponse(500, "Failed to store puzzle", "INSERT_FAILED", correlationId);
    }

    const puzzle = inserted as PublicPuzzleRow;
    const { error: solError } = await admin
      .from("puzzle_solutions")
      .insert({ puzzle_id: puzzle.id, path: generated.referencePath });
    if (solError) {
      // Without a stored solution the puzzle is unusable for hints; roll back.
      lg.error("solution insert failed; rolling back puzzle", { db_error: solError.message });
      await admin.from("puzzles").delete().eq("id", puzzle.id);
      return errorResponse(500, "Failed to store solution", "INSERT_FAILED", correlationId);
    }

    lg.info("puzzle stored", { puzzle_id: puzzle.id });
    return ok({ status: "created", puzzle_date: date, puzzle }, 201);
  } catch (err) {
    log.error("unhandled error", errorFields(err));
    return errorResponse(500, "Internal server error", "INTERNAL", correlationId);
  }
});

async function fetchPublic(
  admin: ReturnType<typeof adminClient>,
  date: string,
): Promise<PublicPuzzleRow | null> {
  const { data, error } = await admin
    .from("puzzles")
    .select(PUBLIC_COLUMNS)
    .eq("puzzle_date", date)
    .maybeSingle();
  if (error) throw new Error(`puzzle lookup failed: ${error.message}`);
  return (data as PublicPuzzleRow | null) ?? null;
}
