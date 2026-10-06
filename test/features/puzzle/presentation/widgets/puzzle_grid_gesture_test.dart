import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icos/features/puzzle/domain/models/puzzle.dart';
import 'package:icos/features/puzzle/presentation/widgets/puzzle_grid.dart';

import '../../../../helpers/test_helpers.dart';

void main() {
  setUpTestEnvironment();

  late List<String> log;

  Future<Rect> pumpGrid(WidgetTester tester, {Puzzle? puzzle}) async {
    log = [];
    await tester.pumpWidget(
      buildTestWidgetInScaffold(
        PuzzleGrid(
          // Frozen state: it never rebuilds between events, like a fast flick
          // that outruns the frame.
          gameState: puzzle == null
              ? createNotStartedGameState()
              : createNotStartedGameState(puzzle: puzzle),
          onCellTap: (r, c) => log.add('tap $r,$c'),
          onCellDrag: (r, c) => log.add('drag $r,$c'),
        ),
      ),
    );
    final box = find
        .descendant(
          of: find.byType(PuzzleGrid),
          matching: find.byType(CustomPaint),
        )
        .first;
    return tester.getRect(box);
  }

  Offset center(Rect board, int row, int col) {
    final c = board.width / 3;
    return board.topLeft + Offset(c * (col + .5), c * (row + .5));
  }

  testWidgets('the path starts where the finger touched down', (tester) async {
    final board = await pumpGrid(tester);
    final c = board.width / 3;
    // Down 4dp inside cell (0,0) from its right edge, cross into (0,1) after
    // 10dp.
    final g = await tester.startGesture(board.topLeft + Offset(c - 4, c / 2));
    await g.moveBy(const Offset(10, 0));
    await tester.pump();
    await g.up();
    expect(log.first, 'drag 0,0');
  });

  testWidgets('two moves inside one frame chain across adjacent cells', (
    tester,
  ) async {
    final board = await pumpGrid(tester);
    final g = await tester.startGesture(center(board, 0, 0));
    await g.moveTo(center(board, 0, 1));
    await g.moveTo(center(board, 0, 2)); // no pump in between
    await tester.pump();
    await g.up();
    expect(log, ['drag 0,0', 'drag 0,1', 'drag 0,2']);
  });

  testWidgets('an invalid second move in the same frame is still rejected', (
    tester,
  ) async {
    // Walls at (0,2) and (1,1) close every way from (0,1) to (1,2).
    final board = await pumpGrid(
      tester,
      puzzle: smallTestPuzzle.copyWith(
        walls: const [Wall(row: 0, col: 2), Wall(row: 1, col: 1)],
      ),
    );
    final g = await tester.startGesture(center(board, 0, 0));
    await g.moveTo(center(board, 0, 1));
    await g.moveTo(center(board, 1, 2)); // no pump in between
    await tester.pump();
    await g.up();
    expect(log, ['drag 0,0', 'drag 0,1']);
  });

  testWidgets('a flick that skips a sample still fills the cells between', (
    tester,
  ) async {
    final board = await pumpGrid(tester);
    final g = await tester.startGesture(center(board, 0, 0));
    await g.moveTo(center(board, 0, 2)); // one event, two cells apart
    await tester.pump();
    await g.up();
    expect(log, ['drag 0,0', 'drag 0,1', 'drag 0,2']);
  });
}
