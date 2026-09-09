import 'package:flutter_test/flutter_test.dart';
import 'package:icos/features/puzzle/domain/solver/puzzle_core.dart';

void expectHamiltonian(int size, Set<int> walls, List<int>? path) {
  expect(path, isNotNull);
  final grid = Grid(size, walls);
  expect(path!.length, grid.openCount);
  expect(path.toSet().length, path.length, reason: 'no duplicates');
  for (final c in path) {
    expect(grid.isOpenIndex(c), isTrue);
  }
  for (var i = 1; i < path.length; i++) {
    expect(grid.adjacent(path[i - 1], path[i]), isTrue, reason: 'step $i');
  }
}

void main() {
  group('findHamiltonianPath', () {
    test('finds a path on open grids of every size', () {
      for (var s = 1; s <= 8; s++) {
        final path = findHamiltonianPath(s, const {}, Rng(s));
        expectHamiltonian(s, const {}, path);
      }
    });

    test('finds a path with walls', () {
      final walls = {0, 7, 30, 44, 63};
      final path = findHamiltonianPath(8, walls, Rng(3));
      expectHamiltonian(8, walls, path);
    });

    test('returns null for infeasible grids', () {
      expect(findHamiltonianPath(3, {1}, Rng(1)), isNull);
      expect(findHamiltonianPath(3, {1, 4, 7}, Rng(1)), isNull);
    });

    test('starts from a degree-one cell when one exists', () {
      // 3x3 with (0,1) and (1,1)... keep parity: remove (0,0) and (0,2)
      // -> (0,1) has a single neighbour (1,1).
      final walls = {0, 2};
      final path = findHamiltonianPath(3, walls, Rng(11));
      expectHamiltonian(3, walls, path);
      expect(path!.first == 1 || path.last == 1, isTrue);
    });

    test('is deterministic per seed and varies across seeds', () {
      final a = findHamiltonianPath(6, {7, 20}, Rng(123));
      final b = findHamiltonianPath(6, {7, 20}, Rng(123));
      final c = findHamiltonianPath(6, {7, 20}, Rng(124));
      expect(a, b);
      expect(a, isNot(c));
    });

    test('respects the node budget', () {
      final path = findHamiltonianPath(8, const {}, Rng(1), nodeBudget: 1);
      // Either found within one node (impossible) or null.
      expect(path, isNull);
    });
  });

  group('backbite', () {
    test('preserves Hamiltonian validity', () {
      final grid = Grid(5, const {});
      final base = findHamiltonianPath(5, const {}, Rng(9), backbiteMoves: 0)!;
      final rng = Rng(42);
      var path = base;
      for (var i = 0; i < 50; i++) {
        path = backbite(grid, path, rng, 3);
        expectHamiltonian(5, const {}, path);
      }
      expect(path, isNot(base));
    });

    test('zero moves returns a copy', () {
      final grid = Grid(3, const {});
      final base = [0, 1, 2, 5, 4, 3, 6, 7, 8];
      final out = backbite(grid, base, Rng(1), 0);
      expect(out, base);
      expect(identical(out, base), isFalse);
    });
  });
}
