/**
 * Tests for puzzle_core.ts. Run with:
 *   deno test -A supabase/functions/_shared/
 */
import {
  type Cell,
  chooseWaypoints,
  countSolutions,
  type Difficulty,
  difficultyParams,
  findHamiltonianPath,
  generatePuzzle,
  Grid,
  isHamiltonianFeasible,
  Rng,
  seedFor,
  toCell,
  validatePath,
  type Waypoint,
  weekdayDifficulty,
} from "./puzzle_core.ts";

// ---------------------------------------------------------------------------
// Minimal assertion helpers (no external deps)
// ---------------------------------------------------------------------------

function assert(cond: boolean, msg: string): void {
  if (!cond) throw new Error(`assertion failed: ${msg}`);
}

function assertEquals<T>(actual: T, expected: T, msg: string): void {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a !== e) throw new Error(`${msg}\n  actual:   ${a}\n  expected: ${e}`);
}

const SIZE_FOR: Record<Difficulty, number> = {
  easy: 5,
  medium: 6,
  hard: 7,
  expert: 8,
};
const DIFFICULTIES: Difficulty[] = ["easy", "medium", "hard", "expert"];

// ---------------------------------------------------------------------------
// seedFor / Rng
// ---------------------------------------------------------------------------

Deno.test("seedFor is FNV-1a 32-bit over `${salt}:${date}`", () => {
  // Reference value computed with an independent FNV-1a implementation.
  assertEquals(seedFor("2026-01-05", "fallback"), 1293688105, "fnv vector");
  assert(
    seedFor("2026-01-05", "fallback") !== seedFor("2026-01-06", "fallback"),
    "date changes seed",
  );
  assert(seedFor("2026-01-05", "fallback") !== seedFor("2026-01-05", "other"), "salt changes seed");
});

Deno.test("Rng is mulberry32 and deterministic", () => {
  const a = new Rng(12345);
  assertEquals(
    [a.nextU32(), a.nextU32(), a.nextU32()],
    [4207900869, 1317490944, 2079646450],
    "mulberry32 reference sequence",
  );
  const b = new Rng(7);
  const c = new Rng(7);
  for (let i = 0; i < 100; i++) {
    const x = b.nextInt(10);
    assertEquals(x, c.nextInt(10), "same seed same stream");
    assert(x >= 0 && x < 10, "nextInt in range");
    const d = b.nextDouble();
    c.nextDouble();
    assert(d >= 0 && d < 1, "nextDouble in [0,1)");
  }
});

// ---------------------------------------------------------------------------
// Grid / feasibility
// ---------------------------------------------------------------------------

Deno.test("Grid exposes open cells and 4-neighbours", () => {
  const g = new Grid(3, [{ row: 1, col: 1 }]);
  assertEquals(g.openCells.length, 8, "8 open cells");
  assert(!g.isOpen(1, 1), "wall is not open");
  assert(!g.isOpen(3, 0), "out of bounds is not open");
  assertEquals(g.neighbors(0).sort(), [1, 3], "corner has 2 neighbours");
  assertEquals(g.neighbors(1).sort(), [0, 2], "wall excluded from neighbours");
});

Deno.test("isHamiltonianFeasible: connectivity and parity", () => {
  assert(isHamiltonianFeasible(5, []), "empty 5x5 feasible");
  // Disconnect the corner (0,0) by walling (0,1) and (1,0).
  assert(
    !isHamiltonianFeasible(5, [{ row: 0, col: 1 }, { row: 1, col: 0 }]),
    "isolated cell is infeasible",
  );
  // 4x4 (8 black / 8 white); removing two same-colour cells → 6 vs 8.
  assert(
    !isHamiltonianFeasible(4, [{ row: 0, col: 0 }, { row: 1, col: 1 }]),
    "parity imbalance 2 is infeasible",
  );
  // Removing one cell from 4x4 → 7 vs 8 is fine.
  assert(isHamiltonianFeasible(4, [{ row: 0, col: 0 }]), "parity imbalance 1 ok");
});

// ---------------------------------------------------------------------------
// findHamiltonianPath
// ---------------------------------------------------------------------------

Deno.test("findHamiltonianPath returns a valid Hamiltonian path (with backbite)", () => {
  for (let seed = 0; seed < 20; seed++) {
    // Walls of opposite colours keep the bipartite balance at 24/23.
    const walls: Cell[] = seed % 2 === 0 ? [] : [{ row: 2, col: 3 }, { row: 5, col: 1 }];
    const size = 7;
    const path = findHamiltonianPath(size, walls, new Rng(seed));
    assert(path !== null, `path found seed=${seed}`);
    const cells = (path as number[]).map((i) => {
      const c = toCell(i, size);
      return [c.row, c.col];
    });
    const wps: Waypoint[] = [
      { order: 1, ...toCell((path as number[])[0], size) },
      { order: 2, ...toCell((path as number[])[cells.length - 1], size) },
    ];
    assertEquals(validatePath(size, walls, wps, cells), { ok: true }, `valid seed=${seed}`);
  }
});

Deno.test("findHamiltonianPath returns null for infeasible grids", () => {
  const path = findHamiltonianPath(4, [{ row: 0, col: 0 }, { row: 1, col: 1 }], new Rng(1), 5_000);
  assertEquals(path, null, "no path on parity-broken grid");
});

// ---------------------------------------------------------------------------
// countSolutions
// ---------------------------------------------------------------------------

Deno.test("countSolutions: parity catches the old broken fallback shape", () => {
  // 5x5, no walls: 13 cells of colour 0 and 12 of colour 1. Endpoints must both
  // be colour 0. (0,4) is colour 0 but (4,3) is colour 1 → impossible.
  const r = countSolutions(5, [], [
    { order: 1, row: 0, col: 4 },
    { order: 2, row: 4, col: 3 },
  ], { limit: 2 });
  assertEquals(r.count, 0, "different-colour endpoints on odd grid");
  assert(!r.exhausted, "search completes");
});

Deno.test("countSolutions: 2x2 grid has exactly one path between adjacent corners", () => {
  const r = countSolutions(2, [], [
    { order: 1, row: 0, col: 0 },
    { order: 2, row: 0, col: 1 },
  ]);
  assertEquals(r.count, 1, "one solution");
  assertEquals(r.solutions[0], [0, 2, 3, 1], "solution indices");
});

Deno.test("countSolutions: 3x3 corner to corner has 2 solutions with endpoints only", () => {
  const r = countSolutions(3, [], [
    { order: 1, row: 0, col: 0 },
    { order: 2, row: 2, col: 2 },
  ], { limit: 10 });
  assertEquals(r.count, 2, "two boustrophedon paths");
});

Deno.test("countSolutions: waypoint order constraint prunes", () => {
  // 3x3 corner-to-corner with (0,2) as waypoint 2: both snakes visit it in
  // order, so still 2 solutions, returned in Warnsdorff/index order.
  const two = countSolutions(3, [], [
    { order: 1, row: 0, col: 0 },
    { order: 2, row: 0, col: 2 },
    { order: 3, row: 2, col: 2 },
  ], { limit: 10 });
  assertEquals(two.count, 2, "two solutions");
  assertEquals(
    two.solutions,
    [[0, 1, 2, 5, 4, 3, 6, 7, 8], [0, 3, 6, 7, 4, 1, 2, 5, 8]],
    "ordered solutions",
  );
  // Requiring (2,0) before (0,2) eliminates the row snake.
  const one = countSolutions(3, [], [
    { order: 1, row: 0, col: 0 },
    { order: 2, row: 2, col: 0 },
    { order: 3, row: 0, col: 2 },
    { order: 4, row: 2, col: 2 },
  ], { limit: 10 });
  assertEquals(one.count, 1, "unique");
  assertEquals(one.solutions[0], [0, 3, 6, 7, 4, 1, 2, 5, 8], "column-first path");
  assert(
    one.nodesAtFirstSolution !== null && one.nodesAtFirstSolution <= one.nodes,
    "first-solution node count",
  );
});

Deno.test("countSolutions: node budget sets exhausted", () => {
  const r = countSolutions(8, [], [
    { order: 1, row: 0, col: 0 },
    { order: 2, row: 7, col: 7 },
  ], { limit: 1_000_000, nodeBudget: 2_000 });
  assert(r.exhausted, "exhausted with tiny budget");
  assert(r.nodes <= 2_001, "stops near budget");
});

// ---------------------------------------------------------------------------
// chooseWaypoints
// ---------------------------------------------------------------------------

Deno.test("chooseWaypoints yields a unique puzzle and pads to target", () => {
  const size = 6;
  const walls: Cell[] = [{ row: 2, col: 2 }];
  const rng = new Rng(99);
  const path = findHamiltonianPath(size, walls, rng) as number[];
  const wps = chooseWaypoints(path, size, walls, rng, {
    maxWaypoints: 10,
    targetWaypoints: 7,
  });
  assert(wps !== null, "waypoints chosen");
  const w = wps as Waypoint[];
  assert(w.length >= 7 && w.length <= 10, `padded to at least 7 (got ${w.length})`);
  assertEquals(w.map((x) => x.order), w.map((_, i) => i + 1), "orders 1..n");
  assertEquals(countSolutions(size, walls, w).count, 1, "unique");
});

// ---------------------------------------------------------------------------
// generatePuzzle
// ---------------------------------------------------------------------------

Deno.test("generatePuzzle is deterministic for a given seed", () => {
  for (const difficulty of DIFFICULTIES) {
    const size = SIZE_FOR[difficulty];
    const seed = seedFor("2026-09-09", `det-${difficulty}`);
    const a = generatePuzzle({ size, difficulty, seed });
    const b = generatePuzzle({ size, difficulty, seed });
    assertEquals(a, b, `deterministic ${difficulty}`);
    const c = generatePuzzle({ size, difficulty, seed: seed + 1000 });
    assert(JSON.stringify(a) !== JSON.stringify(c), `different seed differs ${difficulty}`);
  }
});

Deno.test("generatePuzzle: every puzzle validates and is unique (sizes 5-8, 10 seeds each)", () => {
  const rows: string[] = [];
  for (const difficulty of DIFFICULTIES) {
    const size = SIZE_FOR[difficulty];
    const params = difficultyParams(difficulty);
    const times: number[] = [];
    const counts: number[] = [];
    for (let s = 0; s < 10; s++) {
      const seed = seedFor(`2026-10-${String(s + 1).padStart(2, "0")}`, "test");
      const t0 = performance.now();
      const p = generatePuzzle({ size, difficulty, seed });
      times.push(performance.now() - t0);
      counts.push(p.waypoints.length);

      assertEquals(p.gridSize, size, "gridSize");
      assertEquals(p.difficulty, difficulty, "difficulty");
      assert(
        p.walls.length >= params.wallRange[0] && p.walls.length <= params.wallRange[1],
        `wall count in range ${difficulty}`,
      );
      assert(isHamiltonianFeasible(size, p.walls), "feasible");
      assertEquals(
        validatePath(size, p.walls, p.waypoints, p.referencePath),
        { ok: true },
        `reference path valid ${difficulty} seed ${s}`,
      );
      const c = countSolutions(size, p.walls, p.waypoints, { limit: 2 });
      assertEquals(c.count, 1, `unique ${difficulty} seed ${s}`);
      assert(!c.exhausted, "uniqueness proven");
      assertEquals(
        p.parTimeSeconds,
        Math.round((size * size - p.walls.length) * params.parK),
        "par time",
      );
      assert(p.difficultyScore > 0, "difficulty score");
      if (params.targetWaypoints !== null) {
        assert(
          p.waypoints.length >= params.targetWaypoints[0] &&
            p.waypoints.length <= params.maxWaypoints,
          `waypoint count ${p.waypoints.length} for ${difficulty}`,
        );
      }
    }
    const avg = times.reduce((a, b) => a + b, 0) / times.length;
    rows.push(
      `${size}x${size} ${difficulty.padEnd(6)} avg ${avg.toFixed(1).padStart(6)} ms  max ${
        Math.max(...times).toFixed(1).padStart(6)
      } ms  waypoints ${Math.min(...counts)}-${Math.max(...counts)}`,
    );
  }
  console.log("\n  generatePuzzle timing:\n  " + rows.join("\n  "));
});

Deno.test("generatePuzzle: 8x8 expert typical time under 1.5s", () => {
  const times: number[] = [];
  for (let s = 0; s < 8; s++) {
    const t0 = performance.now();
    generatePuzzle({ size: 8, difficulty: "expert", seed: seedFor(`perf-${s}`, "perf") });
    times.push(performance.now() - t0);
  }
  times.sort((a, b) => a - b);
  const median = times[times.length >> 1];
  console.log(
    `\n  8x8 expert median ${median.toFixed(1)} ms, max ${times[times.length - 1].toFixed(1)} ms`,
  );
  assert(median < 1500, `median ${median}ms under 1.5s`);
});

// ---------------------------------------------------------------------------
// validatePath
// ---------------------------------------------------------------------------

function fixture(): { size: number; walls: Cell[]; waypoints: Waypoint[]; path: number[][] } {
  const p = generatePuzzle({
    size: 5,
    difficulty: "easy",
    seed: seedFor("2026-01-05", "fallback"),
  });
  return { size: 5, walls: p.walls, waypoints: p.waypoints, path: p.referencePath };
}

Deno.test("validatePath accepts the reference path", () => {
  const f = fixture();
  assertEquals(validatePath(f.size, f.walls, f.waypoints, f.path), { ok: true }, "ok");
});

Deno.test("validatePath rejects wrong length", () => {
  const f = fixture();
  const r = validatePath(f.size, f.walls, f.waypoints, f.path.slice(0, -1));
  assertEquals(r, { ok: false, reason: "wrong_length" }, "short path");
});

Deno.test("validatePath rejects duplicates", () => {
  const f = fixture();
  const path = f.path.slice();
  path[1] = path[0];
  assertEquals(
    validatePath(f.size, f.walls, f.waypoints, path),
    { ok: false, reason: "duplicate" },
    "dup",
  );
});

Deno.test("validatePath rejects non-adjacent steps", () => {
  const f = fixture();
  const path = f.path.slice();
  // Swap two interior cells; the set is unchanged but adjacency breaks.
  const tmp = path[3];
  path[3] = path[10];
  path[10] = tmp;
  assertEquals(validatePath(f.size, f.walls, f.waypoints, path), {
    ok: false,
    reason: "not_adjacent",
  }, "swap");
});

Deno.test("validatePath rejects wrong start / wrong end", () => {
  const f = fixture();
  const reversed = f.path.slice().reverse();
  assertEquals(
    validatePath(f.size, f.walls, f.waypoints, reversed),
    { ok: false, reason: "start_not_waypoint_1" },
    "reversed starts at last waypoint",
  );
  // Move the last waypoint so the reference path no longer ends on it.
  const last = f.waypoints[f.waypoints.length - 1];
  const moved = f.waypoints.slice(0, -1).concat([{
    order: last.order,
    row: f.path[1][0],
    col: f.path[1][1],
  }]);
  const r = validatePath(f.size, f.walls, moved, f.path);
  assert(r.ok === false, "moved end rejected");
  assert(
    r.reason === "end_not_last_waypoint" || r.reason === "waypoints_out_of_order",
    `reason ${r.reason}`,
  );
});

Deno.test("validatePath rejects out-of-order waypoints", () => {
  const f = fixture();
  // Swap the orders of waypoints 2 and 3; the path now visits 3 before 2.
  const wps = f.waypoints.map((w) => ({ ...w }));
  const o = wps[1].order;
  wps[1].order = wps[2].order;
  wps[2].order = o;
  assertEquals(
    validatePath(f.size, f.walls, wps, f.path),
    { ok: false, reason: "waypoints_out_of_order" },
    "swapped orders",
  );
});

Deno.test("validatePath rejects walls and out-of-bounds cells", () => {
  const size = 5;
  const walls: Cell[] = [{ row: 2, col: 2 }];
  const p = generatePuzzle({ size, difficulty: "medium", seed: 42 });
  const wallCell = p.walls[0];
  const path = p.referencePath.slice();
  path[2] = [wallCell.row, wallCell.col];
  assertEquals(
    validatePath(size, p.walls, p.waypoints, path),
    { ok: false, reason: "wall" },
    "wall",
  );
  const oob = p.referencePath.slice();
  oob[2] = [-1, 0];
  assertEquals(validatePath(size, p.walls, p.waypoints, oob), {
    ok: false,
    reason: "out_of_bounds",
  }, "oob");
  const malformed = p.referencePath.slice();
  malformed[2] = [1.5, 0];
  assertEquals(validatePath(size, p.walls, p.waypoints, malformed), {
    ok: false,
    reason: "malformed",
  }, "malformed");
  void walls;
});

// ---------------------------------------------------------------------------
// difficulty table / weekday mapping
// ---------------------------------------------------------------------------

Deno.test("difficultyParams exposes the spec table", () => {
  assertEquals(difficultyParams("easy").wallRange, [0, 1], "easy walls");
  assertEquals(difficultyParams("medium").wallRange, [2, 3], "medium walls");
  assertEquals(difficultyParams("hard").wallRange, [3, 5], "hard walls");
  assertEquals(difficultyParams("expert").wallRange, [5, 7], "expert walls");
  assertEquals(difficultyParams("easy").targetWaypoints, [6, 7], "easy target");
  assertEquals(difficultyParams("medium").targetWaypoints, [5, 6], "medium target");
  assertEquals(difficultyParams("hard").targetWaypoints, null, "hard minimal");
  assertEquals(difficultyParams("expert").targetWaypoints, null, "expert minimal");
  assertEquals(
    DIFFICULTIES.map((d) => difficultyParams(d).parK),
    [2.0, 2.4, 2.8, 3.2],
    "par multipliers",
  );
});

Deno.test("weekdayDifficulty uses the UTC weekday", () => {
  // 2026-01-05 is a Monday.
  assertEquals(weekdayDifficulty("2026-01-05"), { gridSize: 5, difficulty: "easy" }, "Mon");
  assertEquals(weekdayDifficulty("2026-01-06"), { gridSize: 5, difficulty: "easy" }, "Tue");
  assertEquals(weekdayDifficulty("2026-01-07"), { gridSize: 6, difficulty: "medium" }, "Wed");
  assertEquals(weekdayDifficulty("2026-01-08"), { gridSize: 6, difficulty: "medium" }, "Thu");
  assertEquals(weekdayDifficulty("2026-01-09"), { gridSize: 7, difficulty: "hard" }, "Fri");
  assertEquals(weekdayDifficulty("2026-01-10"), { gridSize: 7, difficulty: "hard" }, "Sat");
  assertEquals(weekdayDifficulty("2026-01-11"), { gridSize: 8, difficulty: "expert" }, "Sun");
});

// ---------------------------------------------------------------------------
// Parity fixtures (shared with the Dart port)
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

interface ParityFixture {
  cases: ParityCase[];
  puzzles: ParityPuzzle[];
}

Deno.test("parity fixtures agree with the TypeScript implementation", async () => {
  const url = new URL("./fixtures/puzzle_parity.json", import.meta.url);
  const fixtureData = JSON.parse(await Deno.readTextFile(url)) as ParityFixture;
  assert(fixtureData.cases.length >= 12, "at least 12 validatePath cases");
  for (const c of fixtureData.cases) {
    const r = validatePath(c.size, c.walls, c.waypoints, c.path);
    assertEquals(r.ok, c.expectOk, `case ${c.name} ok`);
    assertEquals(r.reason, c.reason, `case ${c.name} reason`);
  }
  assert(fixtureData.puzzles.length >= 3, "at least 3 puzzles");
  for (const p of fixtureData.puzzles) {
    const c = countSolutions(p.size, p.walls, p.waypoints, { limit: 2 });
    assertEquals(c.count, p.expectedSolutionCount, `puzzle ${p.name} count`);
    assertEquals(
      validatePath(p.size, p.walls, p.waypoints, p.referencePath),
      { ok: true },
      `puzzle ${p.name} path`,
    );
    const regenerated = generatePuzzle({ size: p.size, difficulty: p.difficulty, seed: p.seed });
    assertEquals(
      regenerated.referencePath,
      p.referencePath,
      `puzzle ${p.name} regenerates identically`,
    );
    assertEquals(regenerated.difficultyScore, p.difficultyScore, `puzzle ${p.name} score`);
  }
});

// ---------------------------------------------------------------------------
// Bundled fallback puzzles
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

Deno.test("bundled fallback puzzles are solvable, unique and solution-free", async () => {
  const url = new URL("../../../assets/puzzles/fallback_puzzles.json", import.meta.url);
  const puzzles = JSON.parse(await Deno.readTextFile(url)) as Array<
    FallbackPuzzle & Record<string, unknown>
  >;
  assertEquals(puzzles.length, 7, "seven fallback puzzles");
  for (const p of puzzles) {
    assert(
      !("solution" in p) && !("reference_path" in p) && !("solution_hash" in p),
      `${p.id} carries no solution`,
    );
    const expected = weekdayDifficulty(p.puzzle_date);
    assertEquals(p.grid_size, expected.gridSize, `${p.id} grid size`);
    assertEquals(p.difficulty, expected.difficulty, `${p.id} difficulty`);
    const c = countSolutions(p.grid_size, p.walls, p.waypoints, { limit: 2 });
    assertEquals(c.count, 1, `${p.id} unique`);
    assert(!c.exhausted, `${p.id} proven`);
  }
});
