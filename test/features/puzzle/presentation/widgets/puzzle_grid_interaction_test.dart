import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icos/features/puzzle/domain/models/game_state.dart';
import 'package:icos/features/puzzle/domain/models/puzzle.dart';
import 'package:icos/features/puzzle/presentation/widgets/puzzle_grid.dart';

import '../../../../helpers/test_helpers.dart';

/// 3x3 with a wall at (1,1), so the board has a cell that can never be entered.
const _walledPuzzle = Puzzle(
  id: 'walled',
  puzzleDate: '2026-09-11',
  gridSize: 3,
  waypoints: [
    Waypoint(order: 1, row: 0, col: 0),
    Waypoint(order: 2, row: 2, col: 2),
  ],
  walls: [Wall(row: 1, col: 1)],
  difficulty: 'easy',
  parTimeSeconds: 60,
);

void main() {
  group('PuzzleGrid interaction', () {
    /// Records every callback the grid can fire.
    late List<String> events;

    Widget grid({
      GameState? state,
      bool readOnly = false,
    }) {
      return buildTestWidgetInScaffold(
        PuzzleGrid(
          gameState: state ?? createPlayingGameState(),
          readOnly: readOnly,
          onCellTap: (r, c) => events.add('tap $r,$c'),
          onCellDrag: (r, c) => events.add('drag $r,$c'),
          onDragStart: () => events.add('dragStart'),
          onDragEnd: () => events.add('dragEnd'),
          onInvalidMove: (r, c) => events.add('invalid $r,$c'),
        ),
      );
    }

    setUp(() => events = <String>[]);

    Future<void> tapCell(WidgetTester tester, String label) async {
      await tester.tap(find.bySemanticsLabel(label));
      await tester.pump();
    }

    // Path is (0,0) -> (0,1); the head is (0,1).
    testWidgets('tapping the head does nothing at all', (tester) async {
      await tester.pumpWidget(grid());
      await tapCell(tester, 'Row 1, Column 2, filled');
      expect(events, isEmpty);
    });

    testWidgets('tapping a body cell reports it so the line can retract',
        (tester) async {
      await tester.pumpWidget(grid());
      await tapCell(tester, 'Row 1, Column 1, waypoint 1');
      expect(events, ['tap 0,0']);
    });

    testWidgets('tapping an adjacent empty cell extends', (tester) async {
      await tester.pumpWidget(grid());
      await tapCell(tester, 'Row 1, Column 3, empty');
      expect(events, ['tap 0,2']);
    });

    testWidgets('tapping a non-adjacent cell is rejected, not forwarded',
        (tester) async {
      await tester.pumpWidget(grid());
      await tapCell(tester, 'Row 3, Column 1, empty');
      expect(events, ['invalid 2,0']);
    });

    testWidgets('tapping a wall is rejected', (tester) async {
      await tester.pumpWidget(
        grid(state: createPlayingGameState(puzzle: _walledPuzzle)),
      );
      await tapCell(tester, 'Row 2, Column 2, wall');
      expect(events, ['invalid 1,1']);
    });

    testWidgets('before the first move only waypoint 1 is accepted',
        (tester) async {
      await tester.pumpWidget(grid(state: createNotStartedGameState()));
      await tapCell(tester, 'Row 2, Column 2, empty');
      expect(events, ['invalid 1,1']);

      events.clear();
      await tapCell(tester, 'Row 1, Column 1, waypoint 1');
      expect(events, ['tap 0,0']);
    });

    testWidgets('a rejected tap flashes the cell then clears it',
        (tester) async {
      await tester.pumpWidget(grid());
      await tapCell(tester, 'Row 3, Column 1, empty');

      // Mid-flash: the painter has a cell to draw.
      await tester.pump(const Duration(milliseconds: 70));
      expect(tester.takeException(), isNull);

      // The flash plays forward then back, and must not leave state behind.
      // (pumpAndSettle is unusable here: the glow breath loops forever.)
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a drag reports its boundaries and each legal cell crossed',
        (tester) async {
      await tester.pumpWidget(grid());

      final head = tester.getCenter(find.bySemanticsLabel(
        'Row 1, Column 2, filled',
      ));
      final next = tester.getCenter(find.bySemanticsLabel(
        'Row 1, Column 3, empty',
      ));

      final gesture = await tester.startGesture(head);
      await gesture.moveTo(next);
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(events.first, 'dragStart');
      expect(events, contains('drag 0,2'));
      expect(events.last, 'dragEnd');
    });

    testWidgets('a drag over an illegal cell stays silent', (tester) async {
      await tester.pumpWidget(grid());

      final head = tester.getCenter(find.bySemanticsLabel(
        'Row 1, Column 2, filled',
      ));
      final farCorner = tester.getCenter(find.bySemanticsLabel(
        'Row 3, Column 1, empty',
      ));

      final gesture = await tester.startGesture(head);
      await gesture.moveTo(farCorner);
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(events.where((e) => e.startsWith('invalid')), isEmpty);
    });

    // The painter is reused across animation frames, so anything it reads as a
    // plain number is frozen at the value it had when the widget last rebuilt.
    // This pins the flash actually reaching the screen, not just being tracked.
    testWidgets('the invalid flash animates on screen, not just in state',
        (tester) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        buildTestWidgetInScaffold(
          RepaintBoundary(
            key: key,
            child: PuzzleGrid(
              gameState: createPlayingGameState(),
              onCellTap: (_, _) {},
              onCellDrag: (_, _) {},
            ),
          ),
        ),
      );
      await tester.pump();

      final target = find.bySemanticsLabel('Row 3, Column 1, empty');
      final boundaryRect = tester.getRect(find.byKey(key));
      final centre = tester.getCenter(target);

      Future<int> redAtTarget() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        return (await tester.runAsync(() async {
          final image = await boundary.toImage();
          final data =
              await image.toByteData(format: ui.ImageByteFormat.rawRgba);
          final index = (((centre.dy - boundaryRect.top).round()) *
                      image.width +
                  (centre.dx - boundaryRect.left).round()) *
              4;
          final red = data!.buffer.asUint8List()[index];
          image.dispose();
          return red;
        }))!;
      }

      final before = await redAtTarget();
      await tester.tap(target);
      // The first pump starts the ticker; the flash advances from the second.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      final during = await redAtTarget();

      expect(
        during,
        greaterThan(before + 40),
        reason: 'the rejected cell must visibly redden',
      );

      // And it must clear itself again. The reverse leg only starts on the
      // frame after the forward leg completes, so step rather than jump.
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      expect(await redAtTarget(), before);
    });

    testWidgets('readOnly ignores taps and drags', (tester) async {
      await tester.pumpWidget(grid(readOnly: true));

      await tapCell(tester, 'Row 1, Column 3, empty');
      final head = tester.getCenter(find.bySemanticsLabel(
        'Row 1, Column 2, filled',
      ));
      final next = tester.getCenter(find.bySemanticsLabel(
        'Row 1, Column 3, empty',
      ));
      final gesture = await tester.startGesture(head);
      await gesture.moveTo(next);
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(events, isEmpty);
    });
  });
}
