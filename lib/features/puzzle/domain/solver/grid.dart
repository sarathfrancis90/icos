/// Grid geometry for the puzzle core. Cells are addressed by a flat index
/// `row * size + col`. Walls are stored as a set of indices.
library;

import 'dart:typed_data';

/// Direction offsets `(dRow, dCol)` in the canonical order used by both
/// implementations: up, right, down, left.
const List<List<int>> kDirections = [
  [-1, 0],
  [0, 1],
  [1, 0],
  [0, -1],
];

class Grid {
  Grid(this.size, Iterable<int> walls)
      : assert(size > 0, 'size must be positive'),
        walls = Set<int>.unmodifiable(walls) {
    final total = size * size;
    _isWall = Uint8List(total);
    for (final w in this.walls) {
      if (w >= 0 && w < total) _isWall[w] = 1;
    }
    final open = <int>[];
    final nbrs = List<List<int>>.generate(total, (_) => const <int>[]);
    for (var idx = 0; idx < total; idx++) {
      if (_isWall[idx] == 1) continue;
      open.add(idx);
      final r = idx ~/ size;
      final c = idx % size;
      final list = <int>[];
      for (final d in kDirections) {
        final nr = r + d[0];
        final nc = c + d[1];
        if (nr < 0 || nr >= size || nc < 0 || nc >= size) continue;
        final n = nr * size + nc;
        if (_isWall[n] == 1) continue;
        list.add(n);
      }
      nbrs[idx] = List<int>.unmodifiable(list);
    }
    openCells = List<int>.unmodifiable(open);
    _neighbors = nbrs;
  }

  final int size;
  final Set<int> walls;

  /// All open (non-wall) cell indices in row-major order.
  late final List<int> openCells;

  late final Uint8List _isWall;
  late final List<List<int>> _neighbors;

  int get total => size * size;
  int get openCount => openCells.length;

  int index(int row, int col) => row * size + col;
  int rowOf(int idx) => idx ~/ size;
  int colOf(int idx) => idx % size;

  bool inBounds(int row, int col) =>
      row >= 0 && row < size && col >= 0 && col < size;

  bool isWallIndex(int idx) => idx >= 0 && idx < total && _isWall[idx] == 1;

  bool isOpen(int row, int col) =>
      inBounds(row, col) && _isWall[index(row, col)] == 0;

  bool isOpenIndex(int idx) => idx >= 0 && idx < total && _isWall[idx] == 0;

  /// Open 4-neighbours of `idx` in canonical direction order.
  List<int> neighbors(int idx) => _neighbors[idx];

  /// Bipartite colour of a cell (0 or 1).
  int colorOf(int idx) => (rowOf(idx) + colOf(idx)) & 1;

  /// Whether two indices are 4-adjacent.
  bool adjacent(int a, int b) {
    final dr = (rowOf(a) - rowOf(b)).abs();
    final dc = (colOf(a) - colOf(b)).abs();
    return dr + dc == 1;
  }
}

/// Necessary conditions for a Hamiltonian path over the open cells:
/// * connected;
/// * bipartite colour classes differ by at most one;
/// * at most two degree-one cells (they are forced to be endpoints), and their
///   colours must be consistent with the endpoint parity: for an odd cell
///   count both endpoints are the majority colour; for an even count the two
///   endpoints have different colours.
bool isHamiltonianFeasible(int size, Iterable<int> walls) {
  final grid = Grid(size, walls);
  final n = grid.openCount;
  if (n == 0) return false;
  if (n == 1) return true;

  var black = 0;
  var white = 0;
  final degreeOne = <int>[];
  for (final idx in grid.openCells) {
    if (grid.colorOf(idx) == 0) {
      black++;
    } else {
      white++;
    }
    final deg = grid.neighbors(idx).length;
    if (deg == 0) return false;
    if (deg == 1) degreeOne.add(idx);
  }
  if ((black - white).abs() > 1) return false;
  // Degree-one cells must be path endpoints; there are only two endpoints.
  if (degreeOne.length > 2) return false;

  // Endpoint parity.
  if (n.isOdd) {
    final majority = black > white ? 0 : 1;
    for (final idx in degreeOne) {
      if (grid.colorOf(idx) != majority) return false;
    }
  } else if (degreeOne.length == 2 &&
      grid.colorOf(degreeOne[0]) == grid.colorOf(degreeOne[1])) {
    return false;
  }

  // Connectivity.
  final seen = Uint8List(grid.total);
  final stack = <int>[grid.openCells.first];
  seen[grid.openCells.first] = 1;
  var reached = 0;
  while (stack.isNotEmpty) {
    final cur = stack.removeLast();
    reached++;
    for (final nb in grid.neighbors(cur)) {
      if (seen[nb] == 0) {
        seen[nb] = 1;
        stack.add(nb);
      }
    }
  }
  return reached == n;
}
