import 'package:flutter_test/flutter_test.dart';
import 'package:icos/features/puzzle/domain/solver/puzzle_core.dart';

void main() {
  // 3x3 indices:
  //   0 1 2
  //   3 4 5
  //   6 7 8
  const rowSnake = [0, 1, 2, 5, 4, 3, 6, 7, 8];
  const colSnake = [0, 3, 6, 7, 4, 1, 2, 5, 8];

  group('countSolutions', () {
    test('corner to corner on 3x3 has exactly two solutions', () {
      final res = countSolutions(3, const {}, [0, 8], limit: 10);
      expect(res.count, 2);
      expect(res.exhausted, isFalse);
      expect(res.solutions, containsAll([rowSnake, colSnake]));
      for (final s in res.solutions) {
        expect(validatePath(3, const {}, [0, 8], _cells(3, s)).ok, isTrue);
      }
    });

    test('waypoint ordering forces uniqueness', () {
      // (0,2) must precede the centre: only the row snake qualifies.
      final res = countSolutions(3, const {}, [0, 2, 4, 8], limit: 10);
      expect(res.count, 1);
      expect(res.isUnique, isTrue);
      expect(res.solutions.single, rowSnake);
    });

    test('a waypoint visited in both orders keeps both solutions', () {
      final res = countSolutions(3, const {}, [0, 2, 8], limit: 10);
      expect(res.count, 2);
    });

    test('parity-impossible end returns zero without searching', () {
      // A 16-cell path must end on the opposite colour to its start.
      final res = countSolutions(4, const {}, [0, 15], limit: 10);
      expect(res.count, 0);
      expect(res.nodes, lessThanOrEqualTo(1));
    });

    test('impossible end returns zero', () {
      // Ring around a centre wall: a Hamiltonian path from 0 must end at a
      // ring neighbour of 0, so ending at 8 is impossible.
      final res = countSolutions(3, {4}, [0, 8], limit: 10);
      expect(res.count, 0);
      expect(res.exhausted, isFalse);
    });

    test('ring with reachable end is unique', () {
      final res = countSolutions(3, {4}, [0, 1], limit: 10);
      expect(res.count, 1);
      expect(res.solutions.single, [0, 3, 6, 7, 8, 5, 2, 1]);
    });

    test('limit caps the number of returned solutions', () {
      // (0,0) -> (0,3): opposite colours, as a 16-cell path requires.
      final res = countSolutions(4, const {}, [0, 3], limit: 3);
      expect(res.count, 3);
      expect(res.solutions.length, 3);
      expect(res.exhausted, isFalse);
    });

    test('searches from the tighter endpoint but returns forward paths', () {
      // Walls (0,0),(0,2) make (0,1) degree 1: the search starts there and
      // the returned paths are reversed back to start at (1,2).
      final res = countSolutions(3, {0, 2}, [5, 1], limit: 10);
      expect(res.count, greaterThan(0));
      for (final s in res.solutions) {
        expect(s.first, 5);
        expect(s.last, 1);
        expect(validatePath(3, {0, 2}, [5, 1], _cells(3, s)).ok, isTrue);
      }
      expect(res.nodesAtFirstSolution, isNotNull);
      expect(res.nodesAtFirstSolution, lessThanOrEqualTo(res.nodes));
    });

    test('limit 1 reports nodes for difficulty scoring', () {
      final res = countSolutions(5, const {}, [0, 24], limit: 1);
      expect(res.count, 1);
      expect(res.nodes, greaterThan(0));
    });

    test('node budget marks result exhausted', () {
      final res = countSolutions(8, const {}, [0, 7], limit: 2, nodeBudget: 5);
      expect(res.exhausted, isTrue);
      expect(res.nodes, greaterThan(5));
      expect(res.count, lessThan(2));
    });

    test('rejects waypoints on walls or duplicates', () {
      expect(countSolutions(3, {4}, [0, 4]).count, 0);
      expect(countSolutions(3, const {}, [0, 0]).count, 0);
      expect(countSolutions(3, const {}, const []).count, 0);
    });

    test('fewer than two waypoints yields no solutions (TS contract)', () {
      expect(countSolutions(1, const {}, [0]).count, 0);
      expect(countSolutions(2, {1, 2, 3}, [0]).count, 0);
    });

    group('prefix', () {
      test('valid prefix restricts the search', () {
        final res = countSolutions(
          3,
          const {},
          [0, 8],
          limit: 10,
          prefix: [0, 3],
        );
        expect(res.count, 1);
        expect(res.solutions.single, colSnake);
      });

      test('prefix that cannot complete returns zero', () {
        final res = countSolutions(
          3,
          const {},
          [0, 2, 4, 8],
          limit: 10,
          prefix: [0, 3],
        );
        expect(res.count, 0);
      });

      test('invalid prefixes return zero', () {
        // Wrong start.
        expect(
          countSolutions(3, const {}, [0, 8], prefix: [1, 2]).count,
          0,
        );
        // Not adjacent.
        expect(
          countSolutions(3, const {}, [0, 8], prefix: [0, 2]).count,
          0,
        );
        // Duplicate.
        expect(
          countSolutions(3, const {}, [0, 8], prefix: [0, 1, 0]).count,
          0,
        );
        // Waypoint out of order.
        expect(
          countSolutions(3, const {}, [0, 2, 4, 8], prefix: [0, 1, 4]).count,
          0,
        );
        // Reaches the end early.
        expect(
          countSolutions(3, const {}, [0, 1], prefix: [0, 1]).count,
          0,
        );
      });

      test('complete prefix that is a solution counts once', () {
        final res = countSolutions(3, const {}, [0, 8], prefix: rowSnake);
        expect(res.count, 1);
        expect(res.solutions.single, rowSnake);
      });
    });
  });

  group('validatePath', () {
    const size = 3;
    const wps = [0, 8];

    test('accepts a correct path', () {
      final v = validatePath(size, const {}, wps, _cells(size, rowSnake));
      expect(v.ok, isTrue);
      expect(v.reason, isNull);
    });

    test('length mismatch', () {
      final v = validatePath(size, const {}, wps, _cells(size, [0, 1, 2]));
      expect(v.ok, isFalse);
      expect(v.reason, 'wrong_length');
    });

    test('out of bounds', () {
      final cells = _cells(size, rowSnake);
      cells[3] = [1, 3];
      expect(validatePath(size, const {}, wps, cells).reason, 'out_of_bounds');
    });

    test('wall', () {
      // Walls at 4: 8 open cells.
      final cells = _cells(size, [0, 1, 2, 5, 4, 3, 6, 7]);
      expect(validatePath(size, {4}, [0, 7], cells).reason, 'wall');
    });

    test('duplicate', () {
      final cells = _cells(size, [0, 1, 2, 5, 4, 3, 6, 7, 7]);
      expect(validatePath(size, const {}, wps, cells).reason, 'duplicate');
    });

    test('not adjacent', () {
      final cells = _cells(size, [0, 1, 2, 5, 8, 7, 6, 3, 4]);
      // 4 is adjacent to 3, so tweak: jump 2 -> 8.
      final jump = _cells(size, [0, 1, 2, 8, 5, 4, 3, 6, 7]);
      expect(validatePath(size, const {}, [0, 7], jump).reason, 'not_adjacent');
      expect(validatePath(size, const {}, [0, 4], cells).ok, isTrue);
    });

    test('wrong start', () {
      final cells = _cells(size, [2, 1, 0, 3, 4, 5, 8, 7, 6]);
      expect(validatePath(size, const {}, [0, 6], cells).reason, 'start_not_waypoint_1');
    });

    test('wrong end', () {
      final cells = _cells(size, [0, 1, 2, 5, 4, 3, 6, 7, 8]);
      expect(validatePath(size, const {}, [0, 6], cells).reason, 'end_not_last_waypoint');
    });

    test('waypoint order', () {
      final cells = _cells(size, colSnake);
      // colSnake visits 4 (index 4) before 2 (index 6).
      expect(
        validatePath(size, const {}, [0, 2, 4, 8], cells).reason,
        'waypoints_out_of_order',
      );
      // Waypoint not on the path at all (wall-free but missing) is impossible
      // when length matches; a waypoint on a wall is 'waypoints_out_of_order'.
      expect(
        validatePath(size, {4}, [0, 4, 7], _cells(size, [0, 1, 2, 5, 8, 7, 6, 3]))
            .ok,
        isFalse,
      );
    });

    test('malformed cell', () {
      final cells = _cells(size, rowSnake);
      cells[2] = [0];
      expect(validatePath(size, const {}, wps, cells).reason, 'malformed');
      // Fewer than two waypoints is malformed too.
      expect(
        validatePath(size, const {}, [0], _cells(size, rowSnake)).reason,
        'malformed',
      );
    });

    test('checks are ordered per contract', () {
      // A path that is both too short and out of bounds reports wrong_length first.
      final v = validatePath(size, const {}, wps, [
        [0, 0],
        [9, 9],
      ]);
      expect(v.reason, 'wrong_length');
      // Malformed cells win over every other check.
      final tri = _cells(size, rowSnake);
      tri[0] = [0, 0, 0];
      expect(validatePath(size, const {}, wps, tri).reason, 'malformed');
    });
  });
}

List<List<int>> _cells(int size, List<int> indices) =>
    [for (final i in indices) [i ~/ size, i % size]];
