#!/usr/bin/env -S deno run -A
/**
 * Icos puzzle generator CLI.
 *
 *   deno run -A scripts/generate_puzzles.ts fallback
 *       Regenerates assets/puzzles/fallback_puzzles.json (7 puzzles, Mon..Sun,
 *       NO solutions) and prints a verification table.
 *
 *   deno run -A scripts/generate_puzzles.ts daily --from 2026-09-10 --days 14 --salt $PUZZLE_SEED_SALT [--dry-run]
 *       Prints JSON rows (puzzle + solution). When SUPABASE_URL and
 *       SUPABASE_SERVICE_ROLE_KEY are set (and not --dry-run) upserts into
 *       `puzzles` and `puzzle_solutions` via PostgREST.
 *
 *   deno run -A scripts/generate_puzzles.ts verify [path]
 *       Verifies every puzzle in a fallback-format JSON file has exactly one
 *       solution (defaults to the bundled fallback file).
 *
 *   deno run -A scripts/generate_puzzles.ts fixtures
 *       Regenerates supabase/functions/_shared/fixtures/puzzle_parity.json.
 */
import {
  type Cell,
  countSolutions,
  type Difficulty,
  type GeneratedPuzzle,
  generatePuzzle,
  seedFor,
  validatePath,
  type Waypoint,
  weekdayDifficulty,
} from "../supabase/functions/_shared/puzzle_core.ts";

const REPO_ROOT = new URL("../", import.meta.url);
const FALLBACK_PATH = new URL("assets/puzzles/fallback_puzzles.json", REPO_ROOT);
const FIXTURE_PATH = new URL(
  "supabase/functions/_shared/fixtures/puzzle_parity.json",
  REPO_ROOT,
);

const WEEKDAYS = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"] as const;
/** 2026-01-05 is a Monday; the fallback dates are Mon..Sun of that week. */
const FALLBACK_DATES = [
  "2026-01-05",
  "2026-01-06",
  "2026-01-07",
  "2026-01-08",
  "2026-01-09",
  "2026-01-10",
  "2026-01-11",
];

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface FallbackPuzzle {
  id: string;
  puzzle_date: string;
  grid_size: number;
  waypoints: Waypoint[];
  walls: Cell[];
  difficulty: Difficulty;
  par_time_seconds: number;
  difficulty_score: number;
}

interface PuzzleRow {
  puzzle_date: string;
  grid_size: number;
  waypoints: Waypoint[];
  walls: Cell[];
  difficulty: Difficulty;
  par_time_seconds: number;
  difficulty_score: number;
  seed_version: number;
}

interface DailyOutput {
  puzzle: PuzzleRow;
  solution: number[][];
}

interface Args {
  command: string;
  flags: Map<string, string | true>;
  positional: string[];
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function parseArgs(argv: string[]): Args {
  const [command = "help", ...rest] = argv;
  const flags = new Map<string, string | true>();
  const positional: string[] = [];
  for (let i = 0; i < rest.length; i++) {
    const a = rest[i];
    if (!a.startsWith("--")) {
      positional.push(a);
      continue;
    }
    const key = a.slice(2);
    const next = rest[i + 1];
    if (next !== undefined && !next.startsWith("--")) {
      flags.set(key, next);
      i++;
    } else {
      flags.set(key, true);
    }
  }
  return { command, flags, positional };
}

function flagString(args: Args, key: string): string | undefined {
  const v = args.flags.get(key);
  return typeof v === "string" ? v : undefined;
}

function addDays(dateStr: string, days: number): string {
  const d = new Date(`${dateStr}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}

function toPuzzleRow(date: string, p: GeneratedPuzzle): PuzzleRow {
  return {
    puzzle_date: date,
    grid_size: p.gridSize,
    waypoints: p.waypoints,
    walls: p.walls,
    difficulty: p.difficulty,
    par_time_seconds: p.parTimeSeconds,
    difficulty_score: p.difficultyScore,
    seed_version: 2,
  };
}

function generateForDate(date: string, salt: string): GeneratedPuzzle {
  const { gridSize, difficulty } = weekdayDifficulty(date);
  return generatePuzzle({ size: gridSize, difficulty, seed: seedFor(date, salt) });
}

/** Prints a fixed-width verification table; returns false if any puzzle fails. */
function verifyTable(puzzles: FallbackPuzzle[]): boolean {
  const header = "id            date        size diff    walls wps solutions nodes    status";
  console.log(header);
  console.log("-".repeat(header.length));
  let allOk = true;
  for (const p of puzzles) {
    const r = countSolutions(p.grid_size, p.walls, p.waypoints, { limit: 2 });
    const ok = r.count === 1 && !r.exhausted;
    allOk &&= ok;
    console.log(
      `${p.id.padEnd(13)} ${p.puzzle_date}  ${String(p.grid_size).padStart(4)} ${
        p.difficulty.padEnd(7)
      } ${String(p.walls.length).padStart(5)} ${String(p.waypoints.length).padStart(3)} ${
        String(r.count).padStart(9)
      } ${String(r.nodes).padStart(8)} ${ok ? "OK" : (r.exhausted ? "EXHAUSTED" : "FAIL")}`,
    );
  }
  return allOk;
}

// ---------------------------------------------------------------------------
// Commands
// ---------------------------------------------------------------------------

async function cmdFallback(): Promise<void> {
  const puzzles: FallbackPuzzle[] = FALLBACK_DATES.map((date, i) => {
    const weekday = WEEKDAYS[i];
    const id = `fallback-${weekday}`;
    const { gridSize, difficulty } = weekdayDifficulty(date);
    const p = generatePuzzle({
      size: gridSize,
      difficulty,
      seed: seedFor(id, "fallback"),
    });
    return {
      id,
      puzzle_date: date,
      grid_size: p.gridSize,
      waypoints: p.waypoints,
      walls: p.walls,
      difficulty: p.difficulty,
      par_time_seconds: p.parTimeSeconds,
      difficulty_score: p.difficultyScore,
    };
  });
  await Deno.writeTextFile(FALLBACK_PATH, JSON.stringify(puzzles, null, 2) + "\n");
  console.log(`wrote ${puzzles.length} puzzles to ${FALLBACK_PATH.pathname}\n`);
  if (!verifyTable(puzzles)) {
    console.error("\nverification FAILED");
    Deno.exit(1);
  }
  console.log("\nall fallback puzzles verified unique");
}

async function cmdVerify(args: Args): Promise<void> {
  const path = args.positional[0] ?? FALLBACK_PATH.pathname;
  const puzzles = JSON.parse(await Deno.readTextFile(path)) as FallbackPuzzle[];
  if (!verifyTable(puzzles)) Deno.exit(1);
}

async function cmdDaily(args: Args): Promise<void> {
  const from = flagString(args, "from");
  const days = Number(flagString(args, "days") ?? "1");
  const salt = flagString(args, "salt") ?? Deno.env.get("PUZZLE_SEED_SALT");
  const dryRun = args.flags.has("dry-run");
  if (from === undefined || !/^\d{4}-\d{2}-\d{2}$/.test(from)) {
    throw new Error("daily requires --from YYYY-MM-DD");
  }
  if (!Number.isInteger(days) || days < 1) throw new Error("--days must be a positive integer");
  if (salt === undefined || salt.length === 0) {
    throw new Error("daily requires --salt or PUZZLE_SEED_SALT");
  }

  const rows: DailyOutput[] = [];
  for (let i = 0; i < days; i++) {
    const date = addDays(from, i);
    const p = generateForDate(date, salt);
    const check = validatePath(p.gridSize, p.walls, p.waypoints, p.referencePath);
    if (!check.ok) {
      throw new Error(`generated puzzle for ${date} failed validation: ${check.reason}`);
    }
    rows.push({ puzzle: toPuzzleRow(date, p), solution: p.referencePath });
  }
  console.log(JSON.stringify(rows, null, 2));

  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (dryRun) {
    console.error(`dry run: skipped upsert of ${rows.length} rows`);
    return;
  }
  if (url === undefined || key === undefined) {
    console.error("SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY not set: skipped upsert");
    return;
  }
  await upsertRows(url, key, rows);
}

// ---------------------------------------------------------------------------
// PostgREST upsert (no supabase-js dependency)
// ---------------------------------------------------------------------------

async function postgrest<T>(
  baseUrl: string,
  key: string,
  table: string,
  onConflict: string,
  body: unknown,
): Promise<T> {
  const res = await fetch(
    `${baseUrl.replace(/\/$/, "")}/rest/v1/${table}?on_conflict=${onConflict}`,
    {
      method: "POST",
      headers: {
        apikey: key,
        Authorization: `Bearer ${key}`,
        "Content-Type": "application/json",
        Prefer: "resolution=merge-duplicates,return=representation",
      },
      body: JSON.stringify(body),
    },
  );
  if (!res.ok) {
    throw new Error(`${table} upsert failed: ${res.status} ${await res.text()}`);
  }
  return await res.json() as T;
}

async function upsertRows(url: string, key: string, rows: DailyOutput[]): Promise<void> {
  const inserted = await postgrest<Array<{ id: string; puzzle_date: string }>>(
    url,
    key,
    "puzzles",
    "puzzle_date",
    rows.map((r) => r.puzzle),
  );
  const idByDate = new Map(inserted.map((r) => [r.puzzle_date, r.id]));
  const solutions = rows.map((r) => {
    const id = idByDate.get(r.puzzle.puzzle_date);
    if (id === undefined) throw new Error(`no puzzle id returned for ${r.puzzle.puzzle_date}`);
    return { puzzle_id: id, path: r.solution };
  });
  await postgrest<unknown[]>(url, key, "puzzle_solutions", "puzzle_id", solutions);
  console.error(`upserted ${rows.length} puzzles + solutions`);
}

// ---------------------------------------------------------------------------
// Parity fixtures for the Dart port
// ---------------------------------------------------------------------------

interface ParityCase {
  name: string;
  size: number;
  walls: Cell[];
  waypoints: Waypoint[];
  path: number[][];
  expectOk: boolean;
  reason?: string;
}

interface ParityPuzzle {
  name: string;
  size: number;
  difficulty: Difficulty;
  seed: number;
  walls: Cell[];
  waypoints: Waypoint[];
  referencePath: number[][];
  expectedSolutionCount: number;
  difficultyScore: number;
  parTimeSeconds: number;
}

function makeCase(
  name: string,
  size: number,
  p: { walls: Cell[]; waypoints: Waypoint[] },
  path: number[][],
): ParityCase {
  const r = validatePath(size, p.walls, p.waypoints, path);
  return {
    name,
    size,
    walls: p.walls,
    waypoints: p.waypoints,
    path,
    expectOk: r.ok,
    reason: r.reason,
  };
}

/** A Hamiltonian path from waypoint 1 to a cell that is not the last waypoint. */
function pathToWrongEnd(size: number, p: GeneratedPuzzle): number[][] | null {
  const start = p.waypoints[0];
  const last = p.waypoints[p.waypoints.length - 1];
  for (let row = 0; row < size; row++) {
    for (let col = 0; col < size; col++) {
      if (row === last.row && col === last.col) continue;
      if (row === start.row && col === start.col) continue;
      if (p.walls.some((w) => w.row === row && w.col === col)) continue;
      const r = countSolutions(size, p.walls, [
        { order: 1, row: start.row, col: start.col },
        { order: 2, row, col },
      ], { limit: 1, nodeBudget: 20_000 });
      if (r.count === 1) {
        return r.solutions[0].map((idx) => [Math.floor(idx / size), idx % size]);
      }
    }
  }
  return null;
}

/** A path with the right endpoints that visits an interior waypoint out of order. */
function pathOutOfOrder(size: number, p: GeneratedPuzzle): number[][] | null {
  const ends = [p.waypoints[0], p.waypoints[p.waypoints.length - 1]].map((w, i) => ({
    ...w,
    order: i + 1,
  }));
  const r = countSolutions(size, p.walls, ends, { limit: 50, nodeBudget: 100_000 });
  for (const sol of r.solutions) {
    const path = sol.map((idx) => [Math.floor(idx / size), idx % size]);
    if (validatePath(size, p.walls, p.waypoints, path).reason === "waypoints_out_of_order") {
      return path;
    }
  }
  return null;
}

async function cmdFixtures(): Promise<void> {
  const easy = generatePuzzle({
    size: 5,
    difficulty: "easy",
    seed: seedFor("parity-easy", "fixture"),
  });
  const medium = generatePuzzle({
    size: 6,
    difficulty: "medium",
    seed: seedFor("parity-medium", "fixture"),
  });
  const hard = generatePuzzle({
    size: 7,
    difficulty: "hard",
    seed: seedFor("parity-hard", "fixture"),
  });
  const expert = generatePuzzle({
    size: 8,
    difficulty: "expert",
    seed: seedFor("parity-expert", "fixture"),
  });

  const cases: ParityCase[] = [];
  cases.push(makeCase("valid_easy_5x5", 5, easy, easy.referencePath));
  cases.push(makeCase("valid_medium_6x6_walls", 6, medium, medium.referencePath));
  cases.push(makeCase("valid_expert_8x8", 8, expert, expert.referencePath));
  cases.push(makeCase("wrong_length_short", 5, easy, easy.referencePath.slice(0, -1)));
  cases.push(
    makeCase("wrong_length_long", 5, easy, easy.referencePath.concat([easy.referencePath[0]])),
  );

  const dup = easy.referencePath.slice();
  dup[1] = dup[0];
  cases.push(makeCase("duplicate_cell", 5, easy, dup));

  const swapped = medium.referencePath.slice();
  const tmp = swapped[4];
  swapped[4] = swapped[12];
  swapped[12] = tmp;
  cases.push(makeCase("not_adjacent_swap", 6, medium, swapped));

  cases.push(
    makeCase("start_not_waypoint_1_reversed", 5, easy, easy.referencePath.slice().reverse()),
  );

  // Some puzzles force their end (a degree-1 cell), so try several.
  const wrongEnd = [easy, medium, hard, expert]
    .map((p) => ({ p, path: pathToWrongEnd(p.gridSize, p) }))
    .find((x) => x.path !== null);
  if (wrongEnd === undefined || wrongEnd.path === null) {
    throw new Error("could not build wrong-end fixture");
  }
  cases.push(makeCase("end_not_last_waypoint", wrongEnd.p.gridSize, wrongEnd.p, wrongEnd.path));

  const outOfOrder = pathOutOfOrder(6, medium) ?? pathOutOfOrder(5, easy);
  if (outOfOrder === null) throw new Error("could not build out-of-order fixture");
  const oooPuzzle = outOfOrder.length === medium.referencePath.length ? medium : easy;
  cases.push(makeCase("waypoints_out_of_order", oooPuzzle.gridSize, oooPuzzle, outOfOrder));

  const throughWall = medium.referencePath.slice();
  throughWall[3] = [medium.walls[0].row, medium.walls[0].col];
  cases.push(makeCase("through_wall", 6, medium, throughWall));

  const oob = hard.referencePath.slice();
  oob[5] = [7, 0];
  cases.push(makeCase("out_of_bounds", 7, hard, oob));

  const malformed = easy.referencePath.slice();
  malformed[2] = [1, 2, 3];
  cases.push(makeCase("malformed_triplet", 5, easy, malformed));

  const puzzles: ParityPuzzle[] = [
    ["parity-easy", "easy", easy],
    ["parity-hard", "hard", hard],
    ["parity-expert", "expert", expert],
  ].map(([name, difficulty, p]) => {
    const puzzle = p as GeneratedPuzzle;
    const count =
      countSolutions(puzzle.gridSize, puzzle.walls, puzzle.waypoints, { limit: 2 }).count;
    return {
      name: name as string,
      size: puzzle.gridSize,
      difficulty: difficulty as Difficulty,
      seed: seedFor(name as string, "fixture"),
      walls: puzzle.walls,
      waypoints: puzzle.waypoints,
      referencePath: puzzle.referencePath,
      expectedSolutionCount: count,
      difficultyScore: puzzle.difficultyScore,
      parTimeSeconds: puzzle.parTimeSeconds,
    };
  });

  const out = {
    description:
      "Parity fixtures for puzzle_core (TS) and its Dart port. `cases` pin validatePath verdicts " +
      "(checked in order: malformed, wrong_length, out_of_bounds, wall, duplicate, not_adjacent, " +
      "start_not_waypoint_1, end_not_last_waypoint, waypoints_out_of_order). `puzzles` pin " +
      "countSolutions(limit 2) counts and the deterministic output of generatePuzzle for a seed.",
    cases,
    puzzles,
  };
  await Deno.writeTextFile(FIXTURE_PATH, JSON.stringify(out, null, 2) + "\n");
  console.log(
    `wrote ${cases.length} cases and ${puzzles.length} puzzles to ${FIXTURE_PATH.pathname}`,
  );
  for (const c of cases) console.log(`  ${c.name.padEnd(32)} ok=${c.expectOk} ${c.reason ?? ""}`);
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

function usage(): void {
  console.log(
    [
      "usage:",
      "  generate_puzzles.ts fallback",
      "  generate_puzzles.ts daily --from YYYY-MM-DD [--days N] [--salt SALT] [--dry-run]",
      "  generate_puzzles.ts verify [path]",
      "  generate_puzzles.ts fixtures",
    ].join("\n"),
  );
}

async function main(): Promise<void> {
  const args = parseArgs(Deno.args);
  switch (args.command) {
    case "fallback":
      await cmdFallback();
      break;
    case "daily":
      await cmdDaily(args);
      break;
    case "verify":
      await cmdVerify(args);
      break;
    case "fixtures":
      await cmdFixtures();
      break;
    default:
      usage();
      Deno.exit(args.command === "help" ? 0 : 1);
  }
}

if (import.meta.main) {
  try {
    await main();
  } catch (err) {
    console.error(err instanceof Error ? err.message : String(err));
    Deno.exit(1);
  }
}
