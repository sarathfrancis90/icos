import 'package:flutter_test/flutter_test.dart';
import 'package:icos/features/puzzle/domain/solver/puzzle_core.dart';

void main() {
  group('Grid', () {
    test('indexes, bounds and walls', () {
      final g = Grid(3, {4});
      expect(g.index(1, 1), 4);
      expect(g.rowOf(7), 2);
      expect(g.colOf(7), 1);
      expect(g.isOpen(1, 1), isFalse);
      expect(g.isOpen(0, 0), isTrue);
      expect(g.isOpen(-1, 0), isFalse);
      expect(g.isOpen(0, 3), isFalse);
      expect(g.openCount, 8);
      expect(g.openCells, [0, 1, 2, 3, 5, 6, 7, 8]);
    });

    test('neighbors exclude walls and out-of-bounds, canonical order', () {
      final g = Grid(3, {4});
      // (0,1): up none, right (0,2)=2, down (1,1)=wall, left (0,0)=0
      expect(g.neighbors(1), [2, 0]);
      // (1,0): up 0, right wall, down 6, left none
      expect(g.neighbors(3), [0, 6]);
      expect(g.neighbors(4), isEmpty);
    });

    test('adjacent and colorOf', () {
      final g = Grid(4, const {});
      expect(g.adjacent(0, 1), isTrue);
      expect(g.adjacent(0, 4), isTrue);
      expect(g.adjacent(0, 5), isFalse);
      expect(g.adjacent(3, 4), isFalse); // row wrap is not adjacent
      expect(g.colorOf(0), 0);
      expect(g.colorOf(1), 1);
      expect(g.colorOf(5), 0);
    });
  });

  group('isHamiltonianFeasible', () {
    test('open grids are feasible', () {
      for (var s = 1; s <= 8; s++) {
        expect(isHamiltonianFeasible(s, const {}), isTrue, reason: 'size $s');
      }
    });

    test('rejects parity imbalance', () {
      // 3x3 with (0,1) removed leaves 5 black vs 3 white cells.
      expect(isHamiltonianFeasible(3, {1}), isFalse);
      // Removing a corner (colour 0) leaves 4 vs 4: feasible.
      expect(isHamiltonianFeasible(3, {0}), isTrue);
    });

    test('rejects disconnected grids', () {
      expect(isHamiltonianFeasible(3, {1, 4, 7}), isFalse);
      expect(isHamiltonianFeasible(4, {1, 5, 9, 13}), isFalse);
    });

    test('rejects more than two degree-one cells', () {
      // 5x5 with walls carving three dead-end stubs.
      // Row 0: . # . # .
      // Row 1: . . . . .
      // Row 2: # # # # #   -> actually disconnected; use a plus shape instead.
      // Plus shape on 3x3: only centre and 4 arms are open -> 4 leaves.
      expect(isHamiltonianFeasible(3, {0, 2, 6, 8}), isFalse);
    });

    test('rejects degree-one cells with the wrong endpoint colour', () {
      // 6x6 minus (0,1),(1,5),(3,0): 33 open cells (odd) so both endpoints
      // must be the majority colour, but the forced endpoints (0,0) and (0,5)
      // have different colours.
      expect(isHamiltonianFeasible(6, {1, 11, 18}), isFalse);
      // 8x8 with a boxed-in (0,1): white, while the majority colour is black.
      expect(isHamiltonianFeasible(8, {0, 2, 5, 24, 46, 56, 63}), isFalse);
      // Even count with two forced endpoints of different colours is fine:
      // 4x4 minus (0,1) and (2,0) forces (0,0) [black] and (3,0) [white].
      expect(isHamiltonianFeasible(4, {1, 8}), isTrue);
      expect(findHamiltonianPath(4, {1, 8}, Rng(1)), isNotNull);
    });

    test('rejects all walls and accepts single cell', () {
      expect(isHamiltonianFeasible(2, {0, 1, 2, 3}), isFalse);
      expect(isHamiltonianFeasible(2, {1, 2, 3}), isTrue);
    });
  });
}
