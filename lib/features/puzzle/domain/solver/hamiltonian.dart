/// Random Hamiltonian path generation: Warnsdorff-ordered DFS with
/// connectivity and dead-end pruning, followed by backbite randomisation.
library;

import 'dart:typed_data';

import 'grid.dart';
import 'rng.dart';

/// Finds a random Hamiltonian path over the open cells of the grid.
///
/// Returns a list of cell indices, or `null` if none was found within
/// [nodeBudget] search nodes (or if the grid is infeasible).
///
/// After a path is found, [backbiteMoves] canonical backbite moves are applied
/// to decorrelate the path from the DFS heuristic (defaults to `8 * openCount`).
List<int>? findHamiltonianPath(
  int size,
  Iterable<int> walls,
  Rng rng, {
  int nodeBudget = 300000,
  int? backbiteMoves,
}) {
  if (!isHamiltonianFeasible(size, walls)) return null;
  final grid = Grid(size, walls);
  final n = grid.openCount;
  if (n == 1) return [grid.openCells.first];

  final starts = _candidateStarts(grid, rng);
  final search = _PathSearch(grid, rng, nodeBudget);
  List<int>? path;
  for (final start in starts) {
    path = search.run(start);
    if (path != null) break;
    if (search.exhausted) break;
  }
  if (path == null) return null;

  final moves = backbiteMoves ?? 8 * n;
  return backbite(grid, path, rng, moves);
}

/// Applies `moves` backbite moves to a Hamiltonian path and returns the new
/// path. A backbite picks an endpoint, chooses a path neighbour of that
/// endpoint other than its predecessor, and reverses the segment between them.
List<int> backbite(Grid grid, List<int> input, Rng rng, int moves) {
  final n = input.length;
  if (n < 3 || moves <= 0) return List<int>.of(input);
  final path = Int32List.fromList(input);
  final pos = Int32List(grid.total)..fillRange(0, grid.total, -1);
  for (var i = 0; i < n; i++) {
    pos[path[i]] = i;
  }

  void reverseRange(int from, int to) {
    var a = from;
    var b = to;
    while (a < b) {
      final t = path[a];
      path[a] = path[b];
      path[b] = t;
      pos[path[a]] = a;
      pos[path[b]] = b;
      a++;
      b--;
    }
  }

  final candidates = <int>[];
  for (var k = 0; k < moves; k++) {
    if (rng.nextInt(2) == 1) reverseRange(0, n - 1);
    final end = path[n - 1];
    candidates.clear();
    for (final nb in grid.neighbors(end)) {
      final p = pos[nb];
      if (p >= 0 && p < n - 2) candidates.add(p);
    }
    if (candidates.isEmpty) continue;
    final i = candidates[rng.nextInt(candidates.length)];
    reverseRange(i + 1, n - 1);
  }
  return List<int>.from(path);
}

List<int> _candidateStarts(Grid grid, Rng rng) {
  var black = 0;
  var white = 0;
  final degreeOne = <int>[];
  for (final idx in grid.openCells) {
    if (grid.colorOf(idx) == 0) {
      black++;
    } else {
      white++;
    }
    if (grid.neighbors(idx).length == 1) degreeOne.add(idx);
  }
  // Degree-one cells must be endpoints, so start from one of them.
  if (degreeOne.isNotEmpty) {
    rng.shuffle(degreeOne);
    return degreeOne;
  }
  final required = black > white
      ? 0
      : white > black
          ? 1
          : -1;
  final starts = <int>[];
  for (final idx in grid.openCells) {
    if (required == -1 || grid.colorOf(idx) == required) starts.add(idx);
  }
  rng.shuffle(starts);
  return starts;
}

class _PathSearch {
  _PathSearch(this.grid, this.rng, this.budget)
      : n = grid.openCount,
        visited = Uint8List(grid.total),
        path = Int32List(grid.openCount),
        _stack = Int32List(grid.total),
        _seen = Uint8List(grid.total);

  final Grid grid;
  final Rng rng;
  final int budget;
  final int n;
  final Uint8List visited;
  final Int32List path;
  final Int32List _stack;
  final Uint8List _seen;

  int nodes = 0;
  bool exhausted = false;

  List<int>? run(int start) {
    visited.fillRange(0, visited.length, 0);
    visited[start] = 1;
    path[0] = start;
    final ok = _dfs(start, 1);
    if (ok) return List<int>.from(path);
    return null;
  }

  bool _dfs(int cur, int depth) {
    if (depth == n) return true;
    nodes++;
    if (nodes > budget) {
      exhausted = true;
      return false;
    }
    if (!_prune(cur, depth)) return false;

    // Warnsdorff ordering with random tie-breaks.
    final cands = <int>[];
    final keys = <double>[];
    for (final nb in grid.neighbors(cur)) {
      if (visited[nb] == 1) continue;
      var deg = 0;
      for (final nn in grid.neighbors(nb)) {
        if (visited[nn] == 0) deg++;
      }
      cands.add(nb);
      keys.add(deg + rng.nextDouble() * 0.5);
    }
    _sortByKey(cands, keys);

    for (final nb in cands) {
      visited[nb] = 1;
      path[depth] = nb;
      if (_dfs(nb, depth + 1)) return true;
      visited[nb] = 0;
      if (exhausted) return false;
    }
    return false;
  }

  bool _prune(int cur, int depth) {
    final remaining = n - depth;
    // Connectivity of unvisited cells from the current cell.
    _seen.fillRange(0, _seen.length, 0);
    var sp = 0;
    var reached = 0;
    for (final nb in grid.neighbors(cur)) {
      if (visited[nb] == 0 && _seen[nb] == 0) {
        _seen[nb] = 1;
        _stack[sp++] = nb;
      }
    }
    while (sp > 0) {
      final c = _stack[--sp];
      reached++;
      for (final nb in grid.neighbors(c)) {
        if (visited[nb] == 0 && _seen[nb] == 0) {
          _seen[nb] = 1;
          _stack[sp++] = nb;
        }
      }
    }
    if (reached != remaining) return false;

    // Dead-end check: at most one unvisited cell may have a single connection
    // (it must become the final cell).
    var singles = 0;
    for (final u in grid.openCells) {
      if (visited[u] == 1) continue;
      var deg = 0;
      for (final nb in grid.neighbors(u)) {
        if (visited[nb] == 0 || nb == cur) deg++;
      }
      if (deg == 0) return false;
      if (deg == 1) {
        singles++;
        if (singles > 1) return false;
      }
    }
    return true;
  }

  static void _sortByKey(List<int> items, List<double> keys) {
    for (var i = 1; i < items.length; i++) {
      final item = items[i];
      final key = keys[i];
      var j = i - 1;
      while (j >= 0 && keys[j] > key) {
        items[j + 1] = items[j];
        keys[j + 1] = keys[j];
        j--;
      }
      items[j + 1] = item;
      keys[j + 1] = key;
    }
  }
}
