// Solves a board described on stdin-ish (via the BOARD env var) and prints the
// solution as "row,col" lines.
//
// Not named `*_test.dart` so `flutter test` and CI skip it. Run it explicitly:
//
//   BOARD='{"size":7,"walls":[[5,6]],"waypoints":[[6,6,1],...]}' \
//     flutter test test/visual/solve_board.dart
//
// Used by the store-screenshot tooling to turn whatever puzzle the app is
// showing today into a tap sequence.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icos/features/puzzle/domain/game_engine.dart';
import 'package:icos/features/puzzle/domain/models/puzzle.dart';

void main() {
  test('solve the board given in BOARD', () {
    final raw = Platform.environment['BOARD'];
    if (raw == null || raw.isEmpty) {
      fail('set BOARD to the puzzle JSON');
    }
    final board = jsonDecode(raw) as Map<String, dynamic>;
    final size = board['size'] as int;

    final walls = [
      for (final w in board['walls'] as List)
        Wall(row: (w as List)[0] as int, col: w[1] as int),
    ];
    final waypoints = [
      for (final w in board['waypoints'] as List)
        Waypoint(
          row: (w as List)[0] as int,
          col: w[1] as int,
          order: w[2] as int,
        ),
    ]..sort((a, b) => a.order.compareTo(b.order));

    final puzzle = Puzzle(
      id: 'from-screen',
      puzzleDate: '2026-09-11',
      gridSize: size,
      waypoints: waypoints,
      walls: walls,
      difficulty: 'unknown',
      parTimeSeconds: 0,
    );

    final solution = solvePuzzle(puzzle, nodeBudget: 4000000);
    expect(solution, isNotNull, reason: 'the board on screen has no solution');

    // ignore: avoid_print
    print('SOLUTION_START');
    for (final p in solution!) {
      // ignore: avoid_print
      print('${p.row},${p.col}');
    }
    // ignore: avoid_print
    print('SOLUTION_END');
  });
}
