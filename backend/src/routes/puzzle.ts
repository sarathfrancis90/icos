// POST /api/start-puzzle and POST /api/daily-puzzle (ports of the edge
// functions of the same names), GET /api/puzzle/:date (no auth, so the app can
// load a puzzle before its guest session exists), plus generateForDate for the
// daily cron.
//
// puzzle/:date -> 200 { puzzle } (public columns, cacheable 5 min)
//   400 INVALID_DATE / DATE_OUT_OF_RANGE (outside the archive window)  404 PUZZLE_NOT_FOUND
//
// start-puzzle  { puzzle_date }  -> 200 { puzzle_date, nonce, started_at, already_completed }
//   Idempotent: the same nonce and the ORIGINAL started_at on every call, so a
//   resumed play keeps submit-score's clock check honest. 404 PUZZLE_NOT_FOUND.
// daily-puzzle  { date? = tomorrow } (users: today or tomorrow UTC only, else
//   403 DATE_NOT_ALLOWED) -> 201 { status:"created", puzzle_date, puzzle } |
//   200 { status:"exists", puzzle_date, puzzle }. The reference solution goes
//   to puzzle_solutions and is never returned.
import { Hono } from "hono";
import { q, tx } from "../db.js";
import {
  addDays,
  compareDates,
  isIsoDate,
  isWithinArchiveWindow,
  Logger,
  randomNonce,
  readJson,
  utcToday,
} from "../shared/http.js";
import { generatePuzzle, seedFor, weekdayDifficulty } from "../shared/puzzle_core.js";
import { PUBLIC_READ_TTL_MS, TtlCache } from "../shared/ttl_cache.js";
import { PUBLIC_CACHE } from "./config.js";
import { activeUser, type ApiDeps, methodNotAllowed, pgError, requestCtx, touchLastActive } from "./common.js";

const NODE_BUDGET = 2_000_000;
const SEED_VERSION = 3;
const FIRST_DATE = "2026-01-01";

/** Public puzzle rows by date, kept in memory for 60 s (found puzzles only). */
export const publicPuzzleCache = new TtlCache<PublicPuzzleRow>(PUBLIC_READ_TTL_MS);

export interface PublicPuzzleRow {
  id: string;
  puzzle_date: string;
  grid_size: number;
  waypoints: unknown;
  walls: unknown;
  difficulty: string;
  par_time_seconds: number;
  difficulty_score: number | null;
  seed_version: number;
  created_at: Date;
}

const PUBLIC_COLUMNS =
  "id, puzzle_date, grid_size, waypoints, walls, difficulty, par_time_seconds, difficulty_score, seed_version, created_at";

/** Raised when a puzzle (or its solution) could not be stored. */
export class PuzzleInsertError extends Error {
  constructor(cause: unknown) {
    super(`puzzle insert failed: ${cause instanceof Error ? cause.message : String(cause)}`, { cause });
    this.name = "PuzzleInsertError";
  }
}

async function fetchPublic(date: string): Promise<PublicPuzzleRow | null> {
  const rows = await q<PublicPuzzleRow>(`SELECT ${PUBLIC_COLUMNS} FROM public.puzzles WHERE puzzle_date = $1 LIMIT 1`, [
    date,
  ]);
  return rows[0] ?? null;
}

/**
 * Returns the puzzle for `date`, generating and storing it (puzzle + reference
 * solution in one transaction) when it does not exist yet. A concurrent writer
 * winning the insert race yields "exists" with the winner's row.
 */
async function ensurePuzzle(
  date: string,
  salt: string,
  log: Logger,
): Promise<{ status: "exists" | "created"; puzzle: PublicPuzzleRow }> {
  const existing = await fetchPublic(date);
  if (existing) {
    log.info("puzzle already exists");
    return { status: "exists", puzzle: existing };
  }

  const { gridSize, difficulty } = weekdayDifficulty(date);
  const t0 = performance.now();
  const generated = generatePuzzle({ size: gridSize, difficulty, seed: seedFor(date, salt), nodeBudget: NODE_BUDGET });
  log.info("puzzle generated", {
    grid_size: generated.gridSize,
    difficulty: generated.difficulty,
    walls: generated.walls.length,
    waypoints: generated.waypoints.length,
    difficulty_score: generated.difficultyScore,
    gen_ms: Math.round(performance.now() - t0),
  });

  try {
    const puzzle = await tx(async (c) => {
      const { rows } = await c.query<PublicPuzzleRow>(
        `INSERT INTO public.puzzles
           (puzzle_date, grid_size, waypoints, walls, difficulty, par_time_seconds, difficulty_score, seed_version)
         VALUES ($1, $2, $3::jsonb, $4::jsonb, $5, $6, $7, $8)
         RETURNING ${PUBLIC_COLUMNS}`,
        [
          date,
          generated.gridSize,
          JSON.stringify(generated.waypoints),
          JSON.stringify(generated.walls),
          generated.difficulty,
          generated.parTimeSeconds,
          generated.difficultyScore,
          SEED_VERSION,
        ],
      );
      await c.query("INSERT INTO public.puzzle_solutions (puzzle_id, path) VALUES ($1, $2::jsonb)", [
        rows[0].id,
        JSON.stringify(generated.referencePath),
      ]);
      return rows[0];
    });
    log.info("puzzle stored", { puzzle_id: puzzle.id });
    return { status: "created", puzzle };
  } catch (err) {
    // 23505 = unique_violation: a concurrent call won the race; return theirs.
    if (pgError(err).code === "23505") {
      const winner = await fetchPublic(date);
      if (winner) {
        log.info("lost insert race; returning existing puzzle");
        return { status: "exists", puzzle: winner };
      }
    }
    throw new PuzzleInsertError(err);
  }
}

/**
 * The cron/backfill path of daily-puzzle: any date from 2026-01-01. Requires
 * PUZZLE_SEED_SALT. Idempotent.
 */
export async function generateForDate(
  date: string,
  log: Logger = new Logger("daily-puzzle", crypto.randomUUID()),
): Promise<"exists" | "created"> {
  const salt = process.env.PUZZLE_SEED_SALT;
  if (!salt) throw new Error("PUZZLE_SEED_SALT is not set");
  if (!isIsoDate(date)) throw new RangeError(`invalid date ${date}; expected YYYY-MM-DD`);
  if (compareDates(date, FIRST_DATE) < 0) throw new RangeError(`date ${date} is before launch`);
  const { status } = await ensurePuzzle(date, salt, log.child({ date, caller: "cron" }));
  return status;
}

export function puzzleRoutes(deps: ApiDeps): Hono {
  const app = new Hono();

  app.all("/puzzle/:date", async (c) => {
    const r = requestCtx(c, deps, "puzzle");
    if (c.req.method !== "GET") return methodNotAllowed(r);
    const date = c.req.param("date");
    if (!isIsoDate(date)) return r.fail(400, "date must be YYYY-MM-DD", "INVALID_DATE");
    if (!isWithinArchiveWindow(date, utcToday())) {
      return r.fail(400, "date is outside the playable window", "DATE_OUT_OF_RANGE");
    }
    let puzzle = publicPuzzleCache.get(date) ?? null;
    if (puzzle === null) {
      puzzle = await fetchPublic(date);
      if (!puzzle) return r.fail(404, "No puzzle for that date", "PUZZLE_NOT_FOUND");
      publicPuzzleCache.set(date, puzzle);
    }
    return r.ok({ puzzle }, 200, PUBLIC_CACHE);
  });

  app.all("/start-puzzle", async (c) => {
    const r = requestCtx(c, deps, "start-puzzle");
    if (c.req.method !== "POST") return methodNotAllowed(r);

    const gate = await activeUser(c, deps, r);
    if (gate instanceof Response) return gate;
    const { user } = gate;

    const body = await readJson(c.req.raw);
    if (body === null) return r.fail(400, "Body must be a JSON object", "INVALID_JSON");
    const puzzleDate = body.puzzle_date;
    if (!isIsoDate(puzzleDate)) return r.fail(400, "puzzle_date must be YYYY-MM-DD", "INVALID_DATE");
    if (!isWithinArchiveWindow(puzzleDate, utcToday())) {
      return r.fail(400, "puzzle_date is outside the playable window", "DATE_OUT_OF_RANGE");
    }
    const lg = r.log.child({ user_id: user.id, puzzle_date: puzzleDate });

    const puzzle = await q("SELECT id FROM public.puzzles WHERE puzzle_date = $1 LIMIT 1", [puzzleDate]);
    if (puzzle.length === 0) return r.fail(404, "No puzzle for that date", "PUZZLE_NOT_FOUND");

    // Insert-if-absent, then read back whichever row exists.
    await q(
      `INSERT INTO public.puzzle_sessions (user_id, puzzle_date, nonce) VALUES ($1, $2, $3)
       ON CONFLICT (user_id, puzzle_date) DO NOTHING`,
      [user.id, puzzleDate, randomNonce(32)],
    );
    const [session] = await q<{ nonce: string; started_at: Date }>(
      "SELECT nonce, started_at FROM public.puzzle_sessions WHERE user_id = $1 AND puzzle_date = $2",
      [user.id, puzzleDate],
    );
    if (!session) throw new Error("session read failed: no row");

    const attempt = await q(
      "SELECT 1 FROM public.puzzle_attempts WHERE user_id = $1 AND puzzle_date = $2 AND completed LIMIT 1",
      [user.id, puzzleDate],
    );
    await touchLastActive(user.id);

    const alreadyCompleted = attempt.length > 0;
    lg.info("session ready", { already_completed: alreadyCompleted });
    return r.ok({
      puzzle_date: puzzleDate,
      nonce: session.nonce,
      started_at: session.started_at,
      already_completed: alreadyCompleted,
    });
  });

  app.all("/daily-puzzle", async (c) => {
    const r = requestCtx(c, deps, "daily-puzzle");
    if (c.req.method !== "POST") return methodNotAllowed(r);

    const salt = process.env.PUZZLE_SEED_SALT;
    if (!salt) {
      r.log.error("PUZZLE_SEED_SALT is not configured; refusing to generate");
      return r.fail(500, "Server misconfigured", "MISSING_SEED_SALT");
    }

    const gate = await activeUser(c, deps, r);
    if (gate instanceof Response) return gate;
    const userId = gate.user.id;

    const body = await readJson(c.req.raw);
    if (body === null) return r.fail(400, "Body must be a JSON object", "INVALID_JSON");
    const today = utcToday();
    const tomorrow = addDays(today, 1);
    const date = body.date === undefined || body.date === null ? tomorrow : body.date;
    if (!isIsoDate(date)) return r.fail(400, "date must be YYYY-MM-DD", "INVALID_DATE");
    if (date !== today && date !== tomorrow) {
      r.log.warn("user requested out-of-window date", { user_id: userId, date });
      return r.fail(403, "Only today's or tomorrow's puzzle can be requested", "DATE_NOT_ALLOWED");
    }

    try {
      const { status, puzzle } = await ensurePuzzle(date, salt, r.log.child({ date, caller: "user", user_id: userId }));
      return r.ok({ status, puzzle_date: date, puzzle }, status === "created" ? 201 : 200);
    } catch (err) {
      if (!(err instanceof PuzzleInsertError)) throw err;
      r.log.error("puzzle insert failed", { db_error: err.message, db_code: pgError(err.cause).code });
      return r.fail(500, "Failed to store puzzle", "INSERT_FAILED");
    }
  });

  return app;
}
