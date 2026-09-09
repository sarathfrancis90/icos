/// Exhaustive puzzle solver used for uniqueness checks, difficulty scoring
/// and hints. Pure Dart; safe to run inside `Isolate.run`.
///
/// Mirrors `supabase/functions/_shared/puzzle_core.ts` (`countSolutions`).
library;

import 'dart:typed_data';

import 'grid.dart';

/// Result of [countSolutions].
class SolveResult {
  const SolveResult({
    required this.count,
    required this.nodes,
    required this.solutions,
    required this.exhausted,
    this.nodesAtFirstSolution,
  });

  static const SolveResult empty = SolveResult(
    count: 0,
    nodes: 0,
    solutions: [],
    exhausted: false,
  );

  /// Number of solutions found (capped at `limit`).
  final int count;

  /// Search nodes expanded.
  final int nodes;

  /// Solutions found, each a list of cell indices from waypoint 1 to the
  /// last waypoint (in that orientation, regardless of the search direction).
  final List<List<int>> solutions;

  /// `true` if the node budget was hit before the search completed; when set,
  /// `count` is a lower bound only.
  final bool exhausted;

  /// Nodes expanded when the first solution was found (difficulty score).
  final int? nodesAtFirstSolution;

  bool get isUnique => count == 1 && !exhausted;
}

/// Counts Hamiltonian paths that satisfy the waypoint ordering.
///
/// `waypoints` are ordered cell indices; the first is the path start and the
/// last is the path end. Stops after `limit` solutions or `nodeBudget` nodes.
///
/// The search runs from whichever endpoint has the lower open degree (the
/// tighter side prunes sooner) and solutions are reversed back so they always
/// run from waypoint 1 to the last waypoint.
///
/// If `prefix` is provided, the search is constrained to paths starting with
/// exactly that sequence of cells (used for hints) and always runs forward.
/// Malformed input (fewer than two waypoints, waypoint on a wall, duplicate
/// waypoints, invalid prefix) yields zero solutions rather than throwing.
SolveResult countSolutions(
  int size,
  Iterable<int> walls,
  List<int> waypoints, {
  int limit = 2,
  int nodeBudget = 300000,
  List<int>? prefix,
}) {
  final grid = Grid(size, walls);
  if (waypoints.length < 2 || limit <= 0) return SolveResult.empty;
  for (final w in waypoints) {
    if (!grid.isOpenIndex(w)) return SolveResult.empty;
  }
  if (waypoints.toSet().length != waypoints.length) return SolveResult.empty;

  var ordered = waypoints;
  var reversed = false;
  if (prefix == null) {
    final firstDeg = grid.neighbors(waypoints.first).length;
    final lastDeg = grid.neighbors(waypoints.last).length;
    if (lastDeg < firstDeg) {
      ordered = waypoints.reversed.toList();
      reversed = true;
    }
  }

  final solver = _Solver(grid, ordered, limit, nodeBudget);
  final result = solver.run(prefix);
  if (!reversed) return result;
  return SolveResult(
    count: result.count,
    nodes: result.nodes,
    solutions: List<List<int>>.unmodifiable(
      [for (final s in result.solutions) s.reversed.toList()],
    ),
    exhausted: result.exhausted,
    nodesAtFirstSolution: result.nodesAtFirstSolution,
  );
}

class _Solver {
  _Solver(this.grid, this.waypoints, this.limit, this.budget)
      : n = grid.openCount,
        visited = Uint8List(grid.total),
        freeDeg = Uint8List(grid.total),
        path = Int32List(grid.openCount),
        wpOrder = Int32List(grid.total)..fillRange(0, grid.total, -1),
        _mark = Int32List(grid.total),
        _stack = Int32List(grid.total) {
    for (var i = 0; i < waypoints.length; i++) {
      wpOrder[waypoints[i]] = i;
    }
    start = waypoints.first;
    end = waypoints.last;
    for (final idx in grid.openCells) {
      freeDeg[idx] = grid.neighbors(idx).length;
      if (grid.colorOf(idx) == 0) {
        _unvisitedBlack++;
      } else {
        _unvisitedWhite++;
      }
    }
  }

  final Grid grid;
  final List<int> waypoints;
  final int limit;
  final int budget;
  final int n;
  final Uint8List visited;

  /// Unvisited open-neighbour count per cell, maintained incrementally.
  final Uint8List freeDeg;
  final Int32List path;
  final Int32List wpOrder;
  final Int32List _mark;
  final Int32List _stack;
  int _generation = 0;

  late final int start;
  late final int end;

  int _unvisitedBlack = 0;
  int _unvisitedWhite = 0;

  int nodes = 0;
  bool exhausted = false;
  int? nodesAtFirstSolution;
  final List<List<int>> solutions = [];

  SolveResult run(List<int>? prefix) {
    if (n == 1) return _result();
    if (start == end) return _result();

    var depth = 0;
    var nextWp = 0;
    final seq = prefix ?? <int>[start];
    if (seq.isEmpty) return _result();
    for (var i = 0; i < seq.length; i++) {
      final cell = seq[i];
      if (!grid.isOpenIndex(cell) || visited[cell] == 1) return _result();
      if (i == 0 && cell != start) return _result();
      if (i > 0 && !grid.adjacent(seq[i - 1], cell)) return _result();
      final order = wpOrder[cell];
      if (order >= 0) {
        if (order != nextWp) return _result();
        nextWp++;
      }
      if (cell == end && i != n - 1) return _result();
      _enter(cell, depth++);
    }
    _dfs(seq.last, depth, nextWp);
    return _result();
  }

  SolveResult _result() => SolveResult(
        count: solutions.length,
        nodes: nodes,
        solutions: List<List<int>>.unmodifiable(solutions),
        exhausted: exhausted,
        nodesAtFirstSolution: nodesAtFirstSolution,
      );

  void _enter(int cell, int depth) {
    visited[cell] = 1;
    path[depth] = cell;
    if (grid.colorOf(cell) == 0) {
      _unvisitedBlack--;
    } else {
      _unvisitedWhite--;
    }
    for (final nb in grid.neighbors(cell)) {
      freeDeg[nb]--;
    }
  }

  void _leave(int cell) {
    visited[cell] = 0;
    if (grid.colorOf(cell) == 0) {
      _unvisitedBlack++;
    } else {
      _unvisitedWhite++;
    }
    for (final nb in grid.neighbors(cell)) {
      freeDeg[nb]++;
    }
  }

  /// Returns `true` when the search should stop (limit reached / budget out).
  bool _dfs(int cur, int depth, int nextWp) {
    nodes++;
    if (nodes > budget) {
      exhausted = true;
      return true;
    }
    final remaining = n - depth;
    if (remaining == 0) {
      // End constraint was enforced on entry.
      if (cur == end && nextWp == waypoints.length) {
        nodesAtFirstSolution ??= nodes;
        solutions.add(List<int>.from(path));
        return solutions.length >= limit;
      }
      return false;
    }

    // Prune 1: bipartite parity. The remaining path alternates colours
    // starting with the opposite colour of cur.
    final curColor = grid.colorOf(cur);
    final oppCount = curColor == 0 ? _unvisitedWhite : _unvisitedBlack;
    if (oppCount != (remaining + 1) >> 1) return false;
    // The colour of the final cell is fixed by the remaining length.
    final lastColor = remaining.isEven ? curColor : 1 - curColor;
    if (grid.colorOf(end) != lastColor) return false;

    // Prune 2 + 3: connectivity and dead ends.
    if (!_remainingIsViable(cur, remaining)) return false;

    // Warnsdorff ordering (stable insertion sort on <= 4 candidates).
    final cands = <int>[];
    for (final nb in grid.neighbors(cur)) {
      if (visited[nb] == 1) continue;
      final deg = freeDeg[nb];
      var j = cands.length;
      cands.add(nb);
      while (j > 0 && freeDeg[cands[j - 1]] > deg) {
        cands[j] = cands[j - 1];
        j--;
      }
      cands[j] = nb;
    }

    for (final nb in cands) {
      final wp = wpOrder[nb];
      // Prune 4: waypoint order; the end cell only as the final cell.
      if (wp >= 0 && wp != nextWp) continue;
      if (nb == end && remaining != 1) continue;
      _enter(nb, depth);
      final stop = _dfs(nb, depth + 1, wp >= 0 ? nextWp + 1 : nextWp);
      _leave(nb);
      if (stop) return true;
    }
    return false;
  }

  /// Flood-fills the unvisited cells reachable from `cur` while checking:
  /// * reachable count == remaining (every unvisited cell, including all
  ///   remaining waypoints, is still reachable);
  /// * the end cell is visited last, so the flood never expands *through*
  ///   it (the end must not be a cut vertex of the unvisited region);
  /// * every unvisited non-end cell has >= 2 available neighbours (counting
  ///   `cur`), the end cell >= 1.
  bool _remainingIsViable(int cur, int remaining) {
    final gen = ++_generation;
    var sp = 0;
    var reached = 0;
    for (final nb in grid.neighbors(cur)) {
      if (visited[nb] == 1 || _mark[nb] == gen) continue;
      _mark[nb] = gen;
      _stack[sp++] = nb;
    }
    while (sp > 0) {
      final c = _stack[--sp];
      reached++;
      var avail = freeDeg[c];
      if (_mark[c] == gen && _isAdjacent(c, cur)) avail++;
      if (c == end) {
        if (avail < 1) return false;
        continue; // never flood through the end cell
      }
      if (avail < 2) return false;
      for (final nb in grid.neighbors(c)) {
        if (visited[nb] == 1 || _mark[nb] == gen) continue;
        _mark[nb] = gen;
        _stack[sp++] = nb;
      }
    }
    return reached == remaining;
  }

  bool _isAdjacent(int a, int b) {
    for (final nb in grid.neighbors(a)) {
      if (nb == b) return true;
    }
    return false;
  }
}
