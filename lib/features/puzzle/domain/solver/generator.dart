/// Puzzle generation, waypoint selection, difficulty parameters and path
/// validation. Pure Dart; safe to run inside `Isolate.run`.
library;

import 'grid.dart';
import 'hamiltonian.dart';
import 'rng.dart';
import 'solver.dart';

enum Difficulty {
  easy,
  medium,
  hard,
  expert;

  static Difficulty parse(String value) {
    for (final d in Difficulty.values) {
      if (d.name == value) return d;
    }
    throw ArgumentError.value(value, 'value', 'Unknown difficulty');
  }
}

class DifficultyParams {
  const DifficultyParams({
    required this.difficulty,
    required this.gridSize,
    required this.minWalls,
    required this.maxWalls,
    required this.minWaypoints,
    required this.maxWaypoints,
    required this.minimal,
    required this.padMin,
    required this.padMax,
    required this.parFactor,
  });

  final Difficulty difficulty;
  final int gridSize;
  final int minWalls;
  final int maxWalls;

  /// Lower bound on waypoint count after padding.
  final int minWaypoints;

  /// Uniqueness loop gives up (regenerate) beyond this many waypoints.
  final int maxWaypoints;

  /// Whether to run the minimality pass (hard/expert).
  final bool minimal;

  /// Padding target range for easy/medium (`null` = no padding).
  final int? padMin;
  final int? padMax;

  /// Seconds-per-open-cell multiplier for par time.
  final double parFactor;
}

/// Product rules: Mon/Tue 5x5 easy, Wed/Thu 6x6 medium, Fri/Sat 7x7 hard,
/// Sun 8x8 expert.
DifficultyParams difficultyParams(Difficulty difficulty) {
  switch (difficulty) {
    case Difficulty.easy:
      return const DifficultyParams(
        difficulty: Difficulty.easy,
        gridSize: 5,
        minWalls: 0,
        maxWalls: 1,
        minWaypoints: 2,
        maxWaypoints: 8,
        minimal: false,
        padMin: 6,
        padMax: 7,
        parFactor: 2.0,
      );
    case Difficulty.medium:
      return const DifficultyParams(
        difficulty: Difficulty.medium,
        gridSize: 6,
        minWalls: 2,
        maxWalls: 3,
        minWaypoints: 2,
        maxWaypoints: 9,
        minimal: false,
        padMin: 5,
        padMax: 6,
        parFactor: 2.4,
      );
    case Difficulty.hard:
      return const DifficultyParams(
        difficulty: Difficulty.hard,
        gridSize: 7,
        minWalls: 3,
        maxWalls: 5,
        minWaypoints: 2,
        maxWaypoints: 10,
        minimal: true,
        padMin: null,
        padMax: null,
        parFactor: 2.8,
      );
    case Difficulty.expert:
      return const DifficultyParams(
        difficulty: Difficulty.expert,
        gridSize: 8,
        minWalls: 5,
        maxWalls: 7,
        minWaypoints: 2,
        maxWaypoints: 14,
        minimal: true,
        padMin: null,
        padMax: null,
        parFactor: 3.2,
      );
  }
}

/// Difficulty for an ISO date string (`YYYY-MM-DD`), interpreted in UTC.
Difficulty weekdayDifficulty(String date) {
  final parsed = DateTime.parse(date);
  final utc = DateTime.utc(parsed.year, parsed.month, parsed.day);
  switch (utc.weekday) {
    case DateTime.monday:
    case DateTime.tuesday:
      return Difficulty.easy;
    case DateTime.wednesday:
    case DateTime.thursday:
      return Difficulty.medium;
    case DateTime.friday:
    case DateTime.saturday:
      return Difficulty.hard;
    default:
      return Difficulty.expert;
  }
}

/// Par time in seconds: `round(openCells * k)`.
int parTimeFor(int openCells, Difficulty difficulty) =>
    (openCells * difficultyParams(difficulty).parFactor).round();

class GeneratedPuzzle {
  const GeneratedPuzzle({
    required this.gridSize,
    required this.difficulty,
    required this.seed,
    required this.walls,
    required this.waypoints,
    required this.referencePath,
    required this.difficultyScore,
    required this.parTimeSeconds,
    required this.attempts,
  });

  final int gridSize;
  final Difficulty difficulty;

  /// The seed that ultimately produced this puzzle (may be a derived retry
  /// seed).
  final int seed;

  /// Wall cell indices in row-major order.
  final List<int> walls;

  /// Ordered waypoint cell indices (first = start, last = end).
  final List<int> waypoints;

  /// The unique solution.
  final List<int> referencePath;

  /// Solver nodes expanded to find the first solution with these waypoints.
  final int difficultyScore;
  final int parTimeSeconds;

  /// Number of generation attempts consumed (1 = first try).
  final int attempts;

  int get openCells => gridSize * gridSize - walls.length;

  List<List<int>> get wallCells =>
      [for (final w in walls) [w ~/ gridSize, w % gridSize]];

  List<List<int>> get waypointCells =>
      [for (final w in waypoints) [w ~/ gridSize, w % gridSize]];

  List<List<int>> get referencePathCells =>
      [for (final c in referencePath) [c ~/ gridSize, c % gridSize]];

  Map<String, dynamic> toJson() => {
        'grid_size': gridSize,
        'difficulty': difficulty.name,
        'seed': seed,
        'walls': [
          for (final w in wallCells) {'row': w[0], 'col': w[1]},
        ],
        'waypoints': [
          for (var i = 0; i < waypointCells.length; i++)
            {
              'order': i + 1,
              'row': waypointCells[i][0],
              'col': waypointCells[i][1],
            },
        ],
        'reference_path': referencePathCells,
        'difficulty_score': difficultyScore,
        'par_time_seconds': parTimeSeconds,
      };
}

class PuzzleGenerationException implements Exception {
  const PuzzleGenerationException(this.message);
  final String message;

  @override
  String toString() => 'PuzzleGenerationException: $message';
}

/// Generates a puzzle with a guaranteed unique solution.
///
/// Retries with seeds `seed + 1, seed + 2, ...` up to [maxAttempts] times if a
/// seed yields an infeasible wall layout, no Hamiltonian path, or no unique
/// waypoint set.
GeneratedPuzzle generatePuzzle({
  required Difficulty difficulty,
  required int seed,
  int? size,
  int nodeBudget = 300000,
  int maxAttempts = 25,
}) {
  final params = difficultyParams(difficulty);
  final gridSize = size ?? params.gridSize;

  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    final attemptSeed = (seed + attempt) & 0xFFFFFFFF;
    final rng = Rng(attemptSeed);

    final wallCount = rng.nextIntInclusive(params.minWalls, params.maxWalls);
    final walls = placeWalls(gridSize, wallCount, rng);
    if (walls == null) continue;

    final path = findHamiltonianPath(
      gridSize,
      walls,
      rng,
      nodeBudget: nodeBudget,
    );
    if (path == null) continue;

    final waypoints = chooseWaypoints(
      path,
      gridSize,
      walls,
      rng,
      minWaypoints: params.minWaypoints,
      maxWaypoints: params.maxWaypoints,
      nodeBudget: nodeBudget,
      minimal: params.minimal,
      padMin: params.padMin,
      padMax: params.padMax,
    );
    if (waypoints == null) continue;

    // Final independent verification (also yields the difficulty score).
    final check = countSolutions(
      gridSize,
      walls,
      waypoints,
      limit: 2,
      nodeBudget: nodeBudget,
    );
    if (!check.isUnique) continue;

    final openCells = gridSize * gridSize - walls.length;
    return GeneratedPuzzle(
      gridSize: gridSize,
      difficulty: difficulty,
      seed: attemptSeed,
      walls: List<int>.unmodifiable(walls.toList()..sort()),
      waypoints: List<int>.unmodifiable(waypoints),
      referencePath: List<int>.unmodifiable(path),
      difficultyScore: check.nodesAtFirstSolution ?? check.nodes,
      parTimeSeconds: parTimeFor(openCells, difficulty),
      attempts: attempt + 1,
    );
  }
  throw PuzzleGenerationException(
    'No unique puzzle after $maxAttempts attempts '
    '(difficulty=${difficulty.name}, seed=$seed)',
  );
}

/// Places `count` walls with a corridor bias: with p=0.6 a wall is placed next
/// to the border or an existing wall, otherwise uniformly. Each placement is
/// rejected if it makes a Hamiltonian path infeasible. Returns `null` when a
/// feasible layout could not be produced.
Set<int>? placeWalls(
  int size,
  int count,
  Rng rng, {
  double corridorBias = 0.6,
  int maxTries = 60,
}) {
  final walls = <int>{};
  if (count <= 0) return walls;
  final total = size * size;

  bool isBorder(int idx) {
    final r = idx ~/ size;
    final c = idx % size;
    return r == 0 || c == 0 || r == size - 1 || c == size - 1;
  }

  bool touchesWall(int idx) {
    final r = idx ~/ size;
    final c = idx % size;
    for (final d in kDirections) {
      final nr = r + d[0];
      final nc = c + d[1];
      if (nr < 0 || nr >= size || nc < 0 || nc >= size) continue;
      if (walls.contains(nr * size + nc)) return true;
    }
    return false;
  }

  var tries = 0;
  while (walls.length < count && tries < maxTries) {
    tries++;
    int candidate;
    if (rng.chance(corridorBias)) {
      final pool = <int>[
        for (var i = 0; i < total; i++)
          if (!walls.contains(i) && (isBorder(i) || touchesWall(i))) i,
      ];
      if (pool.isEmpty) continue;
      candidate = pool[rng.nextInt(pool.length)];
    } else {
      final pool = <int>[
        for (var i = 0; i < total; i++)
          if (!walls.contains(i)) i,
      ];
      candidate = pool[rng.nextInt(pool.length)];
    }
    walls.add(candidate);
    if (!isHamiltonianFeasible(size, walls)) {
      walls.remove(candidate);
    }
  }
  return walls.length == count ? walls : null;
}

/// Chooses ordered waypoints on `path` so the puzzle has exactly one solution.
///
/// Uniqueness loop: start with the endpoints; while a second solution exists,
/// add a reference-path cell that *eliminates* it — a cell whose insertion
/// between its neighbouring waypoints makes solution 2 visit the waypoints
/// out of order — choosing the one farthest from existing waypoints (ties go
/// to the lowest path index). When no single cell eliminates solution 2, or
/// the solver ran out of budget, split the largest gap at its midpoint.
///
/// Then an optional minimality pass (`minimal`) removes redundant interior
/// waypoints, and padding adds evenly spaced helper waypoints up to
/// `padMin..padMax` (adding reference-path waypoints never creates solutions).
///
/// Returns `null` if uniqueness could not be reached within [maxWaypoints].
List<int>? chooseWaypoints(
  List<int> path,
  int size,
  Iterable<int> walls,
  Rng rng, {
  int minWaypoints = 2,
  int maxWaypoints = 12,
  int nodeBudget = 300000,
  bool minimal = false,
  int? padMin,
  int? padMax,
}) {
  final n = path.length;
  if (n < 2) return null;
  final wallSet = walls.toSet();

  // Waypoints are tracked as positions along the reference path.
  final isWp = List<bool>.filled(n, false);
  final positions = <int>[0, n - 1];
  isWp[0] = true;
  isWp[n - 1] = true;

  List<int> cells() {
    final sorted = positions.toList()..sort();
    return [for (final p in sorted) path[p]];
  }

  SolveResult count() =>
      countSolutions(size, wallSet, cells(), limit: 2, nodeBudget: nodeBudget);

  bool addAt(int pi) {
    if (pi < 0 || pi >= n || isWp[pi]) return false;
    if (positions.length >= maxWaypoints) return false;
    isWp[pi] = true;
    positions.add(pi);
    return true;
  }

  // Uniqueness loop.
  while (true) {
    final res = count();
    if (res.count == 0 && !res.exhausted) return null; // path inconsistent
    if (res.isUnique) break;

    var candidate = -1;
    if (res.count >= 2) {
      var other = res.solutions[1];
      for (final s in res.solutions) {
        if (!_samePath(s, path)) {
          other = s;
          break;
        }
      }
      candidate = _eliminatingCell(path, other, positions, isWp, size * size);
    }
    if (candidate < 0) candidate = _largestGapMidpoint(positions);
    if (!addAt(candidate)) return null;
  }

  // Minimality pass.
  if (minimal) {
    final interior = positions.where((p) => p != 0 && p != n - 1).toList();
    rng.shuffle(interior);
    for (final p in interior) {
      if (positions.length <= minWaypoints) break;
      positions.remove(p);
      isWp[p] = false;
      if (!count().isUnique) {
        positions.add(p);
        isWp[p] = true;
      }
    }
  }

  // Padding.
  var target = minWaypoints;
  if (!minimal && padMin != null) {
    final t = rng.nextIntInclusive(padMin, padMax ?? padMin);
    if (t > target) target = t;
  }
  while (positions.length < target) {
    final mid = _largestGapMidpoint(positions);
    if (mid < 0 || !addAt(mid)) break;
  }

  return cells();
}

/// Midpoint of the largest gap between consecutive waypoint positions, or -1
/// if every gap is 1.
int _largestGapMidpoint(List<int> positions) {
  final sorted = positions.toList()..sort();
  var bestGap = 1;
  var best = -1;
  for (var i = 1; i < sorted.length; i++) {
    final gap = sorted[i] - sorted[i - 1];
    if (gap > bestGap) {
      bestGap = gap;
      best = sorted[i - 1] + (gap >> 1);
    }
  }
  return best;
}

/// Path index of a non-waypoint cell whose insertion as a waypoint makes
/// `other` violate the waypoint order (it visits the cell outside the span of
/// its two neighbouring waypoints). Prefers the cell farthest from existing
/// waypoints; ties go to the lowest path index. Returns -1 if none.
int _eliminatingCell(
  List<int> path,
  List<int> other,
  List<int> positions,
  List<bool> isWp,
  int total,
) {
  final posInOther = List<int>.filled(total, -1);
  for (var i = 0; i < other.length; i++) {
    posInOther[other[i]] = i;
  }
  final sorted = positions.toList()..sort();
  var best = -1;
  var bestSpread = -1;
  for (var k = 1; k < sorted.length; k++) {
    final lo = sorted[k - 1];
    final hi = sorted[k];
    final loPos = posInOther[path[lo]];
    final hiPos = posInOther[path[hi]];
    for (var pi = lo + 1; pi < hi; pi++) {
      if (isWp[pi]) continue;
      final pos = posInOther[path[pi]];
      if (pos > loPos && pos < hiPos) continue; // consistent with `other`
      final spread = (pi - lo) < (hi - pi) ? pi - lo : hi - pi;
      if (spread > bestSpread) {
        bestSpread = spread;
        best = pi;
      }
    }
  }
  return best;
}

bool _samePath(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Outcome of [validatePath].
class PathValidation {
  const PathValidation.ok()
      : ok = true,
        reason = null;
  const PathValidation.fail(String this.reason) : ok = false;

  final bool ok;
  final String? reason;

  @override
  String toString() => ok ? 'ok' : 'fail($reason)';
}

/// Validates a submitted path. Contract shared with the server (checked in
/// this order, with these exact reason codes): `malformed`, `wrong_length`,
/// `out_of_bounds`, `wall`, `duplicate`, `not_adjacent`,
/// `start_not_waypoint_1`, `end_not_last_waypoint`, `waypoints_out_of_order`.
///
/// `path` is a list of `[row, col]` pairs; `waypoints` are ordered indices.
PathValidation validatePath(
  int size,
  Iterable<int> walls,
  List<int> waypoints,
  List<List<int>> path,
) {
  final grid = Grid(size, walls);
  if (waypoints.length < 2) return const PathValidation.fail('malformed');
  for (final cell in path) {
    if (cell.length != 2) return const PathValidation.fail('malformed');
  }
  if (path.length != grid.openCount) {
    return const PathValidation.fail('wrong_length');
  }
  final indices = <int>[];
  final seen = <int>{};
  for (final cell in path) {
    final r = cell[0];
    final c = cell[1];
    if (!grid.inBounds(r, c)) return const PathValidation.fail('out_of_bounds');
    final idx = grid.index(r, c);
    if (grid.isWallIndex(idx)) return const PathValidation.fail('wall');
    if (!seen.add(idx)) return const PathValidation.fail('duplicate');
    indices.add(idx);
  }
  for (var i = 1; i < indices.length; i++) {
    if (!grid.adjacent(indices[i - 1], indices[i])) {
      return const PathValidation.fail('not_adjacent');
    }
  }
  if (indices.first != waypoints.first) {
    return const PathValidation.fail('start_not_waypoint_1');
  }
  if (indices.last != waypoints.last) {
    return const PathValidation.fail('end_not_last_waypoint');
  }
  final posOf = <int, int>{};
  for (var i = 0; i < indices.length; i++) {
    posOf[indices[i]] = i;
  }
  var last = -1;
  for (final w in waypoints) {
    final p = posOf[w];
    if (p == null || p <= last) {
      return const PathValidation.fail('waypoints_out_of_order');
    }
    last = p;
  }
  return const PathValidation.ok();
}
