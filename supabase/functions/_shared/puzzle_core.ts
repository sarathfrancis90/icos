/**
 * Icos puzzle core — shared Hamiltonian-path puzzle algorithm.
 *
 * A puzzle is an NxN grid with some wall cells. The player draws ONE
 * continuous 4-adjacent path that visits every non-wall ("open") cell exactly
 * once, passing through numbered waypoints in ascending order. Waypoint 1 is
 * the start of the path and the highest waypoint is the end.
 *
 * This file has NO external imports so it can be loaded unchanged by Deno edge
 * functions, the CLI, and Deno tests. A Dart port of the same algorithm exists
 * on the client; `fixtures/puzzle_parity.json` pins the behaviours both
 * implementations must agree on (validatePath verdicts, solution counts).
 *
 * Cell indexing: `idx = row * size + col`. All internal search state uses
 * indices; the public API accepts/returns `{row, col}` objects except where
 * the spec asks for index arrays (`findHamiltonianPath`, `countSolutions`).
 *
 * Portability notes for the Dart port:
 *   - All integer maths in `seedFor` and `Rng` is unsigned 32-bit. Dart ints
 *     are 64-bit, so mask with `& 0xFFFFFFFF` after every multiply/add.
 *   - Tie-breaks in `countSolutions` are by ascending cell index so `nodes`
 *     counts (used for `difficultyScore`) are identical across ports.
 */

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

export interface Cell {
  row: number;
  col: number;
}

export interface Waypoint extends Cell {
  /** 1-based visiting order. Order 1 is the path start, max order is the end. */
  order: number;
}

export type Difficulty = "easy" | "medium" | "hard" | "expert";

export interface DifficultyParams {
  /** Inclusive [min, max] number of wall cells. */
  wallRange: readonly [number, number];
  /**
   * Inclusive [min, max] total waypoint count to pad to after the uniqueness
   * loop, or `null` when the minimal unique set should be kept instead.
   */
  targetWaypoints: readonly [number, number] | null;
  /** Hard cap on waypoints during the uniqueness loop; regenerate if hit. */
  maxWaypoints: number;
  /** Whether to run the minimality pass (remove redundant interior waypoints). */
  minimize: boolean;
  /** Seconds-per-open-cell multiplier for `parTimeSeconds`. */
  parK: number;
}

export interface CountOptions {
  /** Stop after this many solutions have been found (default 2). */
  limit?: number;
  /** Abort (with `exhausted = true`) after expanding this many nodes. */
  nodeBudget?: number;
}

export interface CountResult {
  /** Number of solutions found (≤ limit). */
  count: number;
  /** Total DFS nodes expanded. */
  nodes: number;
  /** The solutions found, as arrays of cell indices. */
  solutions: number[][];
  /** True if the node budget ran out before the search space was exhausted. */
  exhausted: boolean;
  /** Nodes expanded when the first solution was found (null if none). */
  nodesAtFirstSolution: number | null;
}

export interface ChooseWaypointsOptions {
  minWaypoints?: number;
  maxWaypoints?: number;
  nodeBudget?: number;
  /** Run the minimality pass (hard/expert). */
  minimize?: boolean;
  /** Pad evenly to this many waypoints (easy/medium). Ignored when minimize. */
  targetWaypoints?: number;
}

export interface GeneratePuzzleOptions {
  size: number;
  difficulty: Difficulty;
  seed: number;
  nodeBudget?: number;
}

export interface GeneratedPuzzle {
  gridSize: number;
  walls: Cell[];
  waypoints: Waypoint[];
  /** The generating Hamiltonian path as `[row, col]` pairs. NEVER send to clients. */
  referencePath: number[][];
  /** Solver nodes expanded to reach the first solution (analytics only). */
  difficultyScore: number;
  parTimeSeconds: number;
  difficulty: Difficulty;
}

export interface ValidationResult {
  ok: boolean;
  reason?: string;
}

// ---------------------------------------------------------------------------
// Seeds and RNG
// ---------------------------------------------------------------------------

/** FNV-1a 32-bit hash over the UTF-8 bytes of `${salt}:${date}`. */
export function seedFor(date: string, salt: string): number {
  const bytes = new TextEncoder().encode(`${salt}:${date}`);
  let hash = 0x811c9dc5;
  for (const b of bytes) {
    hash ^= b;
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return hash >>> 0;
}

/** mulberry32 — tiny, fast, deterministic 32-bit PRNG. */
export class Rng {
  private state: number;

  constructor(seed: number) {
    this.state = seed >>> 0;
  }

  /** Next raw unsigned 32-bit value. */
  nextU32(): number {
    this.state = (this.state + 0x6d2b79f5) >>> 0;
    let t = this.state;
    t = Math.imul(t ^ (t >>> 15), t | 1) >>> 0;
    t = (t ^ (t + Math.imul(t ^ (t >>> 7), t | 61))) >>> 0;
    return (t ^ (t >>> 14)) >>> 0;
  }

  /** Uniform double in [0, 1). */
  nextDouble(): number {
    return this.nextU32() / 4294967296;
  }

  /** Uniform integer in [0, n). */
  nextInt(n: number): number {
    if (n <= 0) throw new RangeError("nextInt requires n > 0");
    return Math.floor(this.nextDouble() * n);
  }

  /** In-place Fisher–Yates shuffle. */
  shuffle<T>(items: T[]): T[] {
    for (let i = items.length - 1; i > 0; i--) {
      const j = this.nextInt(i + 1);
      const tmp = items[i];
      items[i] = items[j];
      items[j] = tmp;
    }
    return items;
  }
}

// ---------------------------------------------------------------------------
// Grid
// ---------------------------------------------------------------------------

export function toIndex(row: number, col: number, size: number): number {
  return row * size + col;
}

export function toCell(idx: number, size: number): Cell {
  return { row: Math.floor(idx / size), col: idx % size };
}

/** Bipartite colour of a cell (chessboard parity). */
function colourOf(idx: number, size: number): number {
  const { row, col } = toCell(idx, size);
  return (row + col) & 1;
}

export class Grid {
  readonly size: number;
  readonly walls: ReadonlySet<number>;
  /** Open cell indices in ascending order. */
  readonly openCells: readonly number[];
  /** Flat neighbour table: neighbours of `i` are `adj[i*4 .. i*4+deg[i])`. */
  private readonly adj: Int32Array;
  private readonly deg: Uint8Array;

  constructor(size: number, walls: ReadonlyArray<Cell>) {
    if (!Number.isInteger(size) || size < 1) {
      throw new RangeError(`invalid grid size ${size}`);
    }
    this.size = size;
    const wallSet = new Set<number>();
    for (const w of walls) {
      if (!this.inBounds(w.row, w.col)) {
        throw new RangeError(`wall out of bounds: ${w.row},${w.col}`);
      }
      wallSet.add(toIndex(w.row, w.col, size));
    }
    this.walls = wallSet;

    const n = size * size;
    const open: number[] = [];
    this.adj = new Int32Array(n * 4);
    this.deg = new Uint8Array(n);
    for (let i = 0; i < n; i++) {
      if (wallSet.has(i)) continue;
      open.push(i);
      const { row, col } = toCell(i, size);
      // Fixed neighbour order (up, down, left, right) keeps iteration
      // deterministic; the search sorts candidates anyway.
      const candidates = [
        [row - 1, col],
        [row + 1, col],
        [row, col - 1],
        [row, col + 1],
      ];
      for (const [r, c] of candidates) {
        if (!this.isOpen(r, c)) continue;
        this.adj[i * 4 + this.deg[i]] = toIndex(r, c, size);
        this.deg[i]++;
      }
    }
    this.openCells = open;
  }

  inBounds(row: number, col: number): boolean {
    return row >= 0 && row < this.size && col >= 0 && col < this.size;
  }

  isOpen(row: number, col: number): boolean {
    return this.inBounds(row, col) &&
      !this.walls.has(toIndex(row, col, this.size));
  }

  /** Open 4-neighbours of an open cell index. */
  neighbors(idx: number): number[] {
    const out: number[] = [];
    for (let k = 0; k < this.deg[idx]; k++) out.push(this.adj[idx * 4 + k]);
    return out;
  }

  degree(idx: number): number {
    return this.deg[idx];
  }

  neighborAt(idx: number, k: number): number {
    return this.adj[idx * 4 + k];
  }
}

// ---------------------------------------------------------------------------
// Feasibility
// ---------------------------------------------------------------------------

/**
 * Cheap necessary conditions for a Hamiltonian path to exist:
 *  1. at least one open cell and all open cells connected;
 *  2. bipartite parity: a path alternates colours, so |black - white| ≤ 1;
 *  3. degree: no open cell isolated (when > 1 cell) and at most two cells
 *     of degree 1 (they would have to be the path endpoints);
 *  4. degree-1 cells are forced endpoints, so their colours must match what
 *     parity dictates: on an odd cell count both endpoints have the majority
 *     colour; on an even count the two endpoints have different colours.
 */
export function isHamiltonianFeasible(
  size: number,
  walls: ReadonlyArray<Cell>,
): boolean {
  const grid = new Grid(size, walls);
  const open = grid.openCells;
  if (open.length === 0) return false;
  if (open.length === 1) return true;

  const degOneColours: number[] = [];
  let colour0 = 0;
  for (const idx of open) {
    const d = grid.degree(idx);
    if (d === 0) return false;
    if (d === 1) degOneColours.push(colourOf(idx, size));
    if (colourOf(idx, size) === 0) colour0++;
  }
  if (degOneColours.length > 2) return false;
  const colour1 = open.length - colour0;
  if (Math.abs(colour0 - colour1) > 1) return false;
  if (colour0 !== colour1) {
    const majority = colour0 > colour1 ? 0 : 1;
    if (degOneColours.some((c) => c !== majority)) return false;
  } else if (degOneColours.length === 2 && degOneColours[0] === degOneColours[1]) {
    return false;
  }

  return reachableCount(grid, open[0], null) === open.length;
}

/** BFS count of cells reachable from `start`, skipping `blocked` cells. */
function reachableCount(
  grid: Grid,
  start: number,
  blocked: Uint8Array | null,
): number {
  const n = grid.size * grid.size;
  const seen = new Uint8Array(n);
  const stack: number[] = [start];
  seen[start] = 1;
  let count = 0;
  while (stack.length > 0) {
    const cur = stack.pop() as number;
    count++;
    for (let k = 0; k < grid.degree(cur); k++) {
      const nb = grid.neighborAt(cur, k);
      if (seen[nb] || (blocked !== null && blocked[nb])) continue;
      seen[nb] = 1;
      stack.push(nb);
    }
  }
  return count;
}

// ---------------------------------------------------------------------------
// Core DFS solver (shared by findHamiltonianPath and countSolutions)
// ---------------------------------------------------------------------------

interface SolverConfig {
  grid: Grid;
  start: number;
  /** Fixed end cell, or -1 when any end is acceptable. */
  end: number;
  /** wpOrder[idx] = 0-based waypoint position, or -1 if not a waypoint. */
  wpOrder: Int8Array;
  waypointCount: number;
  limit: number;
  nodeBudget: number;
  /** Optional rng for random tie-breaking (path generation only). */
  rng: Rng | null;
}

/**
 * Depth-first Hamiltonian path search with pruning. Kept as a class so the
 * hot loop can use preallocated typed arrays instead of allocating per node.
 */
class Solver {
  private readonly grid: Grid;
  private readonly size: number;
  private readonly n: number;
  private readonly end: number;
  private readonly wpOrder: Int8Array;
  private readonly waypointCount: number;
  private readonly limit: number;
  private readonly nodeBudget: number;
  private readonly rng: Rng | null;

  private readonly visited: Uint8Array;
  /** Unvisited open neighbour count per cell, maintained incrementally. */
  private readonly freeDeg: Uint8Array;
  private readonly path: Int32Array;
  private readonly colour: Uint8Array;
  private readonly unvisitedByColour = [0, 0];

  // Flood-fill scratch (generation stamps avoid clearing between calls).
  private readonly mark: Int32Array;
  private readonly floodStack: Int32Array;
  private generation = 0;

  nodes = 0;
  exhausted = false;
  nodesAtFirstSolution: number | null = null;
  readonly solutions: number[][] = [];

  constructor(cfg: SolverConfig) {
    this.grid = cfg.grid;
    this.size = cfg.grid.size;
    this.n = this.size * this.size;
    this.end = cfg.end;
    this.wpOrder = cfg.wpOrder;
    this.waypointCount = cfg.waypointCount;
    this.limit = cfg.limit;
    this.nodeBudget = cfg.nodeBudget;
    this.rng = cfg.rng;

    this.visited = new Uint8Array(this.n);
    this.freeDeg = new Uint8Array(this.n);
    this.path = new Int32Array(this.grid.openCells.length);
    this.colour = new Uint8Array(this.n);
    this.mark = new Int32Array(this.n);
    this.floodStack = new Int32Array(this.n);

    for (const idx of this.grid.openCells) {
      this.freeDeg[idx] = this.grid.degree(idx);
      const c = colourOf(idx, this.size);
      this.colour[idx] = c;
      this.unvisitedByColour[c]++;
    }
    this.enter(cfg.start, 0);
  }

  run(): void {
    const start = this.path[0];
    const total = this.grid.openCells.length;
    const nextWp = this.wpOrder[start] >= 0 ? 1 : 0;
    this.dfs(start, 1, total - 1, nextWp);
  }

  private enter(idx: number, depth: number): void {
    this.visited[idx] = 1;
    this.path[depth] = idx;
    this.unvisitedByColour[this.colour[idx]]--;
    for (let k = 0; k < this.grid.degree(idx); k++) {
      this.freeDeg[this.grid.neighborAt(idx, k)]--;
    }
  }

  private leave(idx: number): void {
    this.visited[idx] = 0;
    this.unvisitedByColour[this.colour[idx]]++;
    for (let k = 0; k < this.grid.degree(idx); k++) {
      this.freeDeg[this.grid.neighborAt(idx, k)]++;
    }
  }

  /**
   * @param cur       current (already entered) cell
   * @param depth     number of cells on the path so far
   * @param remaining open cells still unvisited
   * @param nextWp    0-based index of the next waypoint that must be visited
   * @returns true when the search should stop (limit reached / budget out)
   */
  private dfs(
    cur: number,
    depth: number,
    remaining: number,
    nextWp: number,
  ): boolean {
    this.nodes++;
    if (this.nodes > this.nodeBudget) {
      this.exhausted = true;
      return true;
    }

    if (remaining === 0) {
      // Every open cell visited. End constraint was enforced on entry.
      if (this.nodesAtFirstSolution === null) {
        this.nodesAtFirstSolution = this.nodes;
      }
      this.solutions.push(Array.from(this.path.subarray(0, depth)));
      return this.solutions.length >= this.limit;
    }

    // --- Prune 1: bipartite parity. The remaining path alternates colours
    // starting with the opposite colour of `cur`, so the unvisited multiset
    // must contain exactly ceil(rem/2) of the opposite colour.
    const opposite = 1 - this.colour[cur];
    const needOpposite = (remaining + 1) >> 1;
    if (this.unvisitedByColour[opposite] !== needOpposite) return false;

    // --- Prune 2 + 3: connectivity and dead ends (single pass).
    if (!this.remainingIsViable(cur, remaining)) return false;

    // --- Candidate ordering (Warnsdorff): fewest onward options first.
    const cands = this.orderedCandidates(cur);
    for (const nb of cands) {
      const wp = this.wpOrder[nb];
      // --- Prune 4: waypoint order. A waypoint cell may only be entered when
      // it is the next expected one; the end cell only as the final cell.
      if (wp >= 0) {
        if (wp !== nextWp) continue;
        if (nb === this.end && remaining !== 1) continue;
      } else if (nb === this.end && remaining !== 1) {
        continue;
      }
      // An unfixed end still requires all waypoints visited before finishing.
      if (remaining === 1 && (wp >= 0 ? nextWp + 1 : nextWp) !== this.waypointCount) continue;

      this.enter(nb, depth);
      const stop = this.dfs(nb, depth + 1, remaining - 1, wp >= 0 ? nextWp + 1 : nextWp);
      this.leave(nb);
      if (stop) return true;
    }
    return false;
  }

  /**
   * Flood-fills the unvisited cells reachable from `cur` and simultaneously
   * checks dead-end conditions:
   *  - reachable count must equal `remaining` (otherwise some unvisited cell,
   *    including any remaining waypoint, can never be reached);
   *  - the fixed end cell is visited last, so the flood never expands
   *    *through* it: every other unvisited cell must be reachable without
   *    crossing the end (the end must not be a cut vertex);
   *  - every unvisited non-end cell needs ≥ 2 available neighbours (one to
   *    enter, one to leave), counting `cur` as available; the end cell
   *    needs ≥ 1. When the end is not fixed, at most one cell may have only
   *    one available neighbour (it would have to become the end).
   */
  private remainingIsViable(cur: number, remaining: number): boolean {
    this.generation++;
    const gen = this.generation;
    let sp = 0;
    let reached = 0;
    let singles = 0;

    for (let k = 0; k < this.grid.degree(cur); k++) {
      const nb = this.grid.neighborAt(cur, k);
      if (this.visited[nb] || this.mark[nb] === gen) continue;
      this.mark[nb] = gen;
      this.floodStack[sp++] = nb;
    }

    while (sp > 0) {
      const c = this.floodStack[--sp];
      reached++;
      // Available exits: unvisited neighbours plus `cur` if adjacent.
      let avail = this.freeDeg[c];
      if (this.isAdjacent(c, cur)) avail++;
      if (this.end >= 0) {
        if (avail < (c === this.end ? 1 : 2)) return false;
        if (c === this.end) continue; // never flood through the end cell
      } else {
        if (avail === 0) return false;
        if (avail === 1 && ++singles > 1) return false;
      }
      for (let k = 0; k < this.grid.degree(c); k++) {
        const nb = this.grid.neighborAt(c, k);
        if (this.visited[nb] || this.mark[nb] === gen) continue;
        this.mark[nb] = gen;
        this.floodStack[sp++] = nb;
      }
    }
    return reached === remaining;
  }

  private isAdjacent(a: number, b: number): boolean {
    for (let k = 0; k < this.grid.degree(a); k++) {
      if (this.grid.neighborAt(a, k) === b) return true;
    }
    return false;
  }

  private orderedCandidates(cur: number): number[] {
    const cands: number[] = [];
    for (let k = 0; k < this.grid.degree(cur); k++) {
      const nb = this.grid.neighborAt(cur, k);
      if (!this.visited[nb]) cands.push(nb);
    }
    if (this.rng !== null) this.rng.shuffle(cands);
    // Stable sort: ties keep shuffled order (random) or index order (deterministic).
    cands.sort((a, b) =>
      this.freeDeg[a] - this.freeDeg[b] ||
      (this.rng === null ? a - b : 0)
    );
    return cands;
  }
}

// ---------------------------------------------------------------------------
// findHamiltonianPath
// ---------------------------------------------------------------------------

/**
 * Finds a random Hamiltonian path over the open cells, or `null` if none was
 * found within `budget` DFS nodes (summed over restarts).
 *
 * 1. Pick a random start cell. When the open-cell count is odd the path must
 *    start AND end on the majority colour, so restrict starts accordingly.
 * 2. Randomised Warnsdorff DFS with connectivity/dead-end/parity pruning.
 * 3. Apply `K = openCells * 8` canonical backbite moves to decorrelate the
 *    path from Warnsdorff's corner-hugging bias.
 */
export function findHamiltonianPath(
  size: number,
  walls: ReadonlyArray<Cell>,
  rng: Rng,
  budget = 200_000,
): number[] | null {
  const grid = new Grid(size, walls);
  const open = grid.openCells;
  if (open.length === 0) return null;
  if (open.length === 1) return [open[0]];

  let colour0 = 0;
  for (const idx of open) if (colourOf(idx, size) === 0) colour0++;
  const colour1 = open.length - colour0;
  const majority = colour0 === colour1 ? -1 : (colour0 > colour1 ? 0 : 1);
  const starts = open.filter((idx) => majority === -1 || colourOf(idx, size) === majority);

  let used = 0;
  const wpOrder = new Int8Array(size * size).fill(-1);
  while (used < budget) {
    const start = starts[rng.nextInt(starts.length)];
    wpOrder.fill(-1);
    wpOrder[start] = 0;
    const solver = new Solver({
      grid,
      start,
      end: -1,
      wpOrder,
      waypointCount: 1,
      limit: 1,
      nodeBudget: Math.min(budget - used, 20_000),
      rng,
    });
    solver.run();
    used += solver.nodes;
    if (solver.solutions.length > 0) {
      return backbite(grid, solver.solutions[0], rng, open.length * 8);
    }
    // Either this start has no path or its slice of the budget ran out;
    // try another random start until the total budget is spent.
  }
  return null;
}

/**
 * Canonical backbite move: pick an endpoint `e`, pick a random grid-neighbour
 * `v` of `e` that is not `e`'s path-neighbour, and reverse the segment between
 * `e` and the cell adjacent to `v` on `e`'s side. The result is still a
 * Hamiltonian path. `pos[cell]` gives O(1) path-index lookups.
 */
function backbite(
  grid: Grid,
  initial: number[],
  rng: Rng,
  moves: number,
): number[] {
  const path = initial.slice();
  const n = path.length;
  const pos = new Int32Array(grid.size * grid.size).fill(-1);
  for (let i = 0; i < n; i++) pos[path[i]] = i;

  const reverse = (lo: number, hi: number): void => {
    while (lo < hi) {
      const a = path[lo];
      const b = path[hi];
      path[lo] = b;
      path[hi] = a;
      pos[b] = lo;
      pos[a] = hi;
      lo++;
      hi--;
    }
  };

  for (let m = 0; m < moves; m++) {
    const atHead = rng.nextInt(2) === 0;
    const e = atHead ? path[0] : path[n - 1];
    const options: number[] = [];
    for (let k = 0; k < grid.degree(e); k++) {
      const v = grid.neighborAt(e, k);
      const j = pos[v];
      // Exclude the path-neighbour of the endpoint (reversal would be a no-op).
      if (atHead ? j === 1 : j === n - 2) continue;
      options.push(v);
    }
    if (options.length === 0) continue;
    const v = options[rng.nextInt(options.length)];
    const j = pos[v];
    if (atHead) reverse(0, j - 1);
    else reverse(j + 1, n - 1);
  }
  return path;
}

// ---------------------------------------------------------------------------
// countSolutions
// ---------------------------------------------------------------------------

function sortedWaypoints(waypoints: ReadonlyArray<Waypoint>): Waypoint[] {
  return waypoints.slice().sort((a, b) => a.order - b.order);
}

/**
 * Counts Hamiltonian paths that start at waypoint 1, end at the last waypoint
 * and visit waypoints in order, stopping after `limit` solutions.
 *
 * Direction heuristic: a path is the same set of solutions in either
 * direction, but DFS from a low-degree endpoint is far cheaper (its first
 * moves are forced). When the last waypoint has a lower open-neighbour degree
 * than the first, the search runs from the end and every solution is reversed
 * before being returned. Ports must apply the same rule for identical `nodes`.
 */
export function countSolutions(
  size: number,
  walls: ReadonlyArray<Cell>,
  waypoints: ReadonlyArray<Waypoint>,
  options: CountOptions = {},
): CountResult {
  const limit = options.limit ?? 2;
  const nodeBudget = options.nodeBudget ?? 300_000;
  if (waypoints.length < 2) {
    throw new RangeError("countSolutions requires at least 2 waypoints");
  }
  const grid = new Grid(size, walls);
  let ordered = sortedWaypoints(waypoints);
  for (const w of ordered) {
    if (!grid.isOpen(w.row, w.col)) {
      throw new RangeError(`waypoint ${w.order} is not an open cell`);
    }
  }
  const firstDeg = grid.degree(toIndex(ordered[0].row, ordered[0].col, size));
  const lastIdx = ordered[ordered.length - 1];
  const reversed = grid.degree(toIndex(lastIdx.row, lastIdx.col, size)) < firstDeg;
  if (reversed) ordered = ordered.slice().reverse();
  const wpOrder = new Int8Array(size * size).fill(-1);
  ordered.forEach((w, i) => {
    wpOrder[toIndex(w.row, w.col, size)] = i;
  });
  const start = toIndex(ordered[0].row, ordered[0].col, size);
  const end = toIndex(
    ordered[ordered.length - 1].row,
    ordered[ordered.length - 1].col,
    size,
  );

  const empty: CountResult = {
    count: 0,
    nodes: 0,
    solutions: [],
    exhausted: false,
    nodesAtFirstSolution: null,
  };
  if (grid.openCells.length === 0 || start === end) return empty;

  const solver = new Solver({
    grid,
    start,
    end,
    wpOrder,
    waypointCount: ordered.length,
    limit,
    nodeBudget,
    rng: null,
  });
  solver.run();
  const solutions = reversed
    ? solver.solutions.map((sol) => sol.slice().reverse())
    : solver.solutions;
  return {
    count: solutions.length,
    nodes: solver.nodes,
    solutions,
    exhausted: solver.exhausted,
    nodesAtFirstSolution: solver.nodesAtFirstSolution,
  };
}

// ---------------------------------------------------------------------------
// chooseWaypoints
// ---------------------------------------------------------------------------

function waypointsFromIndices(
  path: ReadonlyArray<number>,
  pathIndices: ReadonlyArray<number>,
  size: number,
): Waypoint[] {
  const sorted = pathIndices.slice().sort((a, b) => a - b);
  return sorted.map((pi, i) => ({ order: i + 1, ...toCell(path[pi], size) }));
}

/** Path index of the largest gap midpoint not already used, or -1. */
function largestGapMidpoint(pathIndices: ReadonlyArray<number>): number {
  const sorted = pathIndices.slice().sort((a, b) => a - b);
  let bestGap = 1;
  let best = -1;
  for (let i = 1; i < sorted.length; i++) {
    const gap = sorted[i] - sorted[i - 1];
    if (gap > bestGap) {
      bestGap = gap;
      best = sorted[i - 1] + (gap >> 1);
    }
  }
  return best;
}

/**
 * Chooses ordered waypoints along `path` such that `path` is the unique
 * solution.
 *
 * Uniqueness loop: start with the endpoints; while a second solution exists,
 * add a reference-path cell that *eliminates* it. A cell `c` eliminates
 * solution 2 when inserting it between its neighbouring waypoints (in path
 * order) makes solution 2 visit the waypoints out of order. Among all such
 * cells we pick the one farthest from existing waypoints (ties → lowest path
 * index) so clues spread across the grid. When no single cell can eliminate
 * solution 2 (always the case while only the endpoints exist, since any
 * interior cell lies "between" them in every solution) — or when the solver's
 * budget ran out — we split the largest gap between waypoints at its midpoint.
 *
 * Returns `null` when `maxWaypoints` would be exceeded (caller regenerates).
 */
export function chooseWaypoints(
  path: ReadonlyArray<number>,
  size: number,
  walls: ReadonlyArray<Cell>,
  rng: Rng,
  options: ChooseWaypointsOptions = {},
): Waypoint[] | null {
  const minWaypoints = options.minWaypoints ?? 2;
  const maxWaypoints = options.maxWaypoints ?? 12;
  const nodeBudget = options.nodeBudget ?? 300_000;
  const n = path.length;
  if (n < 2) return null;

  const isWp = new Uint8Array(n);
  const pathIndices: number[] = [0, n - 1];
  isWp[0] = 1;
  isWp[n - 1] = 1;

  const count = (): CountResult =>
    countSolutions(size, walls, waypointsFromIndices(path, pathIndices, size), {
      limit: 2,
      nodeBudget,
    });

  const addAt = (pi: number): boolean => {
    if (pi < 0 || pi >= n || isWp[pi]) return false;
    if (pathIndices.length >= maxWaypoints) return false;
    isWp[pi] = 1;
    pathIndices.push(pi);
    return true;
  };

  // --- Uniqueness loop -----------------------------------------------------
  for (;;) {
    const result = count();
    if (result.count === 0 && !result.exhausted) {
      throw new Error("reference path is not a solution of its own puzzle");
    }
    if (result.count === 1 && !result.exhausted) break;

    let candidate = -1;
    if (result.count >= 2) {
      const other = result.solutions.find((s) => !sameSequence(s, path)) ??
        result.solutions[1];
      candidate = eliminatingCell(path, other, pathIndices, isWp, size);
    }
    if (candidate < 0) candidate = largestGapMidpoint(pathIndices);
    if (!addAt(candidate)) return null;
  }

  // --- Minimality pass -----------------------------------------------------
  if (options.minimize) {
    const interior = rng.shuffle(pathIndices.filter((pi) => pi !== 0 && pi !== n - 1));
    for (const pi of interior) {
      if (pathIndices.length <= minWaypoints) break;
      const at = pathIndices.indexOf(pi);
      pathIndices.splice(at, 1);
      isWp[pi] = 0;
      const r = count();
      if (r.count !== 1 || r.exhausted) {
        pathIndices.push(pi);
        isWp[pi] = 1;
      }
    }
  }

  // --- Padding (adding waypoints can never create new solutions) -----------
  const target = Math.max(
    minWaypoints,
    options.minimize ? 0 : (options.targetWaypoints ?? 0),
  );
  while (pathIndices.length < target) {
    const mid = largestGapMidpoint(pathIndices);
    if (mid < 0 || !addAt(mid)) break;
  }

  return waypointsFromIndices(path, pathIndices, size);
}

/**
 * Finds the path index of a non-waypoint cell whose insertion as a waypoint
 * makes `other` violate the waypoint order, i.e. `other` visits the cell
 * outside the span of its two neighbouring waypoints. Returns -1 if none.
 */
function eliminatingCell(
  path: ReadonlyArray<number>,
  other: ReadonlyArray<number>,
  pathIndices: ReadonlyArray<number>,
  isWp: Uint8Array,
  size: number,
): number {
  const posInOther = new Int32Array(size * size).fill(-1);
  other.forEach((cell, i) => {
    posInOther[cell] = i;
  });
  const sorted = pathIndices.slice().sort((a, b) => a - b);

  let best = -1;
  let bestSpread = -1;
  for (let k = 1; k < sorted.length; k++) {
    const lo = sorted[k - 1];
    const hi = sorted[k];
    const loPos = posInOther[path[lo]];
    const hiPos = posInOther[path[hi]];
    for (let pi = lo + 1; pi < hi; pi++) {
      if (isWp[pi]) continue;
      const pos = posInOther[path[pi]];
      if (pos > loPos && pos < hiPos) continue; // consistent with `other`
      const spread = Math.min(pi - lo, hi - pi);
      if (spread > bestSpread) {
        bestSpread = spread;
        best = pi;
      }
    }
  }
  return best;
}

function sameSequence(a: ReadonlyArray<number>, b: ReadonlyArray<number>): boolean {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return false;
  return true;
}

// ---------------------------------------------------------------------------
// Difficulty
// ---------------------------------------------------------------------------

const DIFFICULTY_TABLE: Record<Difficulty, DifficultyParams> = {
  easy: {
    wallRange: [0, 1],
    targetWaypoints: [6, 7],
    maxWaypoints: 8,
    minimize: false,
    parK: 2.0,
  },
  medium: {
    wallRange: [2, 3],
    targetWaypoints: [5, 6],
    maxWaypoints: 9,
    minimize: false,
    parK: 2.4,
  },
  hard: {
    wallRange: [3, 5],
    targetWaypoints: null,
    maxWaypoints: 10,
    minimize: true,
    parK: 2.8,
  },
  expert: {
    wallRange: [5, 7],
    targetWaypoints: null,
    maxWaypoints: 14,
    minimize: true,
    parK: 3.2,
  },
};

export function difficultyParams(difficulty: Difficulty): DifficultyParams {
  const params = DIFFICULTY_TABLE[difficulty];
  if (params === undefined) throw new RangeError(`unknown difficulty ${difficulty}`);
  return params;
}

/**
 * Product rule (UTC weekday of a `YYYY-MM-DD` string):
 * Mon/Tue 5x5 easy, Wed/Thu 6x6 medium, Fri/Sat 7x7 hard, Sun 8x8 expert.
 */
export function weekdayDifficulty(
  dateStr: string,
): { gridSize: number; difficulty: Difficulty } {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(dateStr)) {
    throw new RangeError(`invalid date ${dateStr}; expected YYYY-MM-DD`);
  }
  const day = new Date(`${dateStr}T00:00:00Z`).getUTCDay(); // 0 = Sunday
  if (Number.isNaN(day)) throw new RangeError(`invalid date ${dateStr}`);
  switch (day) {
    case 1:
    case 2:
      return { gridSize: 5, difficulty: "easy" };
    case 3:
    case 4:
      return { gridSize: 6, difficulty: "medium" };
    case 5:
    case 6:
      return { gridSize: 7, difficulty: "hard" };
    default:
      return { gridSize: 8, difficulty: "expert" };
  }
}

// ---------------------------------------------------------------------------
// generatePuzzle
// ---------------------------------------------------------------------------

/**
 * Places `count` walls with a corridor bias: with p = 0.6 the wall is chosen
 * among cells adjacent to the border or to an existing wall, else uniformly.
 * Retries whole sets that fail `isHamiltonianFeasible` up to 200 times.
 */
function placeWalls(size: number, rng: Rng, params: DifficultyParams): Cell[] | null {
  const [lo, hi] = params.wallRange;
  const count = lo + rng.nextInt(hi - lo + 1);
  for (let attempt = 0; attempt < 200; attempt++) {
    const walls: Cell[] = [];
    const taken = new Set<number>();
    while (walls.length < count) {
      const biased = rng.nextDouble() < 0.6;
      const pool: number[] = [];
      for (let idx = 0; idx < size * size; idx++) {
        if (taken.has(idx)) continue;
        if (!biased || isCorridorCandidate(idx, size, taken)) pool.push(idx);
      }
      if (pool.length === 0) break;
      const idx = pool[rng.nextInt(pool.length)];
      taken.add(idx);
      walls.push(toCell(idx, size));
    }
    if (walls.length === count && isHamiltonianFeasible(size, walls)) {
      walls.sort((a, b) => a.row - b.row || a.col - b.col);
      return walls;
    }
  }
  return null;
}

function isCorridorCandidate(idx: number, size: number, walls: Set<number>): boolean {
  const { row, col } = toCell(idx, size);
  if (row === 0 || col === 0 || row === size - 1 || col === size - 1) return true;
  const around = [
    [row - 1, col],
    [row + 1, col],
    [row, col - 1],
    [row, col + 1],
  ];
  return around.some(([r, c]) => walls.has(toIndex(r, c, size)));
}

/**
 * Deterministically generates a puzzle with exactly one solution. Internally
 * retries with seeds `seed + 1, seed + 2, ...` (max 25 attempts) and throws
 * if none succeeds.
 */
export function generatePuzzle(options: GeneratePuzzleOptions): GeneratedPuzzle {
  const { size, difficulty, seed } = options;
  const nodeBudget = options.nodeBudget ?? 300_000;
  const params = difficultyParams(difficulty);

  for (let attempt = 0; attempt < 25; attempt++) {
    const rng = new Rng((seed + attempt) >>> 0);
    const walls = placeWalls(size, rng, params);
    if (walls === null) continue;

    const path = findHamiltonianPath(size, walls, rng);
    if (path === null) continue;

    const [tLo, tHi] = params.targetWaypoints ?? [0, 0];
    const target = tLo + rng.nextInt(tHi - tLo + 1);
    const waypoints = chooseWaypoints(path, size, walls, rng, {
      minWaypoints: 2,
      maxWaypoints: params.maxWaypoints,
      nodeBudget,
      minimize: params.minimize,
      targetWaypoints: target,
    });
    if (waypoints === null) continue;

    // Final independent verification (also yields the difficulty score).
    const check = countSolutions(size, walls, waypoints, { limit: 2, nodeBudget });
    if (check.count !== 1 || check.exhausted) continue;

    const openCells = size * size - walls.length;
    return {
      gridSize: size,
      walls,
      waypoints,
      referencePath: path.map((idx) => {
        const c = toCell(idx, size);
        return [c.row, c.col];
      }),
      difficultyScore: check.nodesAtFirstSolution ?? check.nodes,
      parTimeSeconds: Math.round(openCells * params.parK),
      difficulty,
    };
  }
  throw new Error(
    `generatePuzzle: no unique puzzle for size=${size} difficulty=${difficulty} seed=${seed}`,
  );
}

// ---------------------------------------------------------------------------
// validatePath
// ---------------------------------------------------------------------------

/**
 * Validates a submitted path. Server and client MUST agree, so checks run in
 * this fixed order and return these exact reason codes:
 *   malformed, wrong_length, out_of_bounds, wall, duplicate, not_adjacent,
 *   start_not_waypoint_1, end_not_last_waypoint, waypoints_out_of_order
 */
export function validatePath(
  size: number,
  walls: ReadonlyArray<Cell>,
  waypoints: ReadonlyArray<Waypoint>,
  path: ReadonlyArray<ReadonlyArray<number>>,
): ValidationResult {
  const grid = new Grid(size, walls);
  const ordered = sortedWaypoints(waypoints);
  if (ordered.length < 2) return { ok: false, reason: "malformed" };
  for (const step of path) {
    if (
      step.length !== 2 || !Number.isInteger(step[0]) ||
      !Number.isInteger(step[1])
    ) {
      return { ok: false, reason: "malformed" };
    }
  }
  if (path.length !== grid.openCells.length) {
    return { ok: false, reason: "wrong_length" };
  }

  const seen = new Uint8Array(size * size);
  const indices: number[] = [];
  for (const [r, c] of path) {
    if (!grid.inBounds(r, c)) return { ok: false, reason: "out_of_bounds" };
    const idx = toIndex(r, c, size);
    if (grid.walls.has(idx)) return { ok: false, reason: "wall" };
    if (seen[idx]) return { ok: false, reason: "duplicate" };
    seen[idx] = 1;
    indices.push(idx);
  }
  for (let i = 1; i < indices.length; i++) {
    const a = toCell(indices[i - 1], size);
    const b = toCell(indices[i], size);
    if (Math.abs(a.row - b.row) + Math.abs(a.col - b.col) !== 1) {
      return { ok: false, reason: "not_adjacent" };
    }
  }

  const first = ordered[0];
  const last = ordered[ordered.length - 1];
  if (indices[0] !== toIndex(first.row, first.col, size)) {
    return { ok: false, reason: "start_not_waypoint_1" };
  }
  if (indices[indices.length - 1] !== toIndex(last.row, last.col, size)) {
    return { ok: false, reason: "end_not_last_waypoint" };
  }

  const position = new Int32Array(size * size).fill(-1);
  indices.forEach((idx, i) => {
    position[idx] = i;
  });
  let prev = -1;
  for (const w of ordered) {
    const p = position[toIndex(w.row, w.col, size)];
    if (p <= prev) return { ok: false, reason: "waypoints_out_of_order" };
    prev = p;
  }
  return { ok: true };
}
