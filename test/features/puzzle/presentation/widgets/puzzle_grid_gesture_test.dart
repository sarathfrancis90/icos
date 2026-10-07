import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icos/features/puzzle/domain/game_engine.dart';
import 'package:icos/features/puzzle/domain/models/game_state.dart';
import 'package:icos/features/puzzle/domain/models/puzzle.dart';
import 'package:icos/features/puzzle/presentation/widgets/puzzle_grid.dart';

import '../../../../helpers/storage_test_helpers.dart';
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

  group('exact grid walk (5x5)', () {
    late Directory dir;
    setUp(() async => dir = await initTestStorage());
    tearDown(() async => dir.delete(recursive: true));

    const five = Puzzle(
      id: 'five',
      puzzleDate: '2026-10-06',
      gridSize: 5,
      waypoints: [
        Waypoint(order: 1, row: 0, col: 0),
        Waypoint(order: 2, row: 4, col: 4),
      ],
      walls: [],
      difficulty: 'easy',
      parTimeSeconds: 60,
    );

    /// A point in board cell units (1.0 = one cell).
    Offset at(Rect board, double row, double col) {
      final c = board.width / 5;
      return board.topLeft + Offset(c * col, c * row);
    }

    Future<TestGesture> begin(
      WidgetTester tester,
      Rect board,
      double row,
      double col,
    ) => tester.startGesture(at(board, row, col));

    testWidgets('centre-to-centre diagonal fills nothing', (tester) async {
      final board = await pumpGrid(tester, puzzle: five);
      final g = await begin(tester, board, .5, .5);
      await g.moveTo(at(board, 1.5, 1.5));
      await tester.pump();
      await g.up();
      expect(log, ['drag 0,0']);
    });

    testWidgets('off-centre diagonal clearly through one corner fills it', (
      tester,
    ) async {
      final board = await pumpGrid(tester, puzzle: five);
      final g = await begin(tester, board, .5, .9);
      await g.moveTo(at(board, 1.1, 1.5));
      await tester.pump();
      await g.up();
      expect(log, ['drag 0,0', 'drag 0,1', 'drag 1,1']);
    });

    testWidgets('a diagonal within 0.2 cell of the corner fills nothing', (
      tester,
    ) async {
      final board = await pumpGrid(tester, puzzle: five);
      final g = await begin(tester, board, .8, .95);
      await g.moveTo(at(board, 1.2, 1.5));
      await tester.pump();
      await g.up();
      expect(log, ['drag 0,0']);
    });

    testWidgets('a jump across three cells in a row fills them in order', (
      tester,
    ) async {
      final board = await pumpGrid(tester, puzzle: five);
      final g = await begin(tester, board, .5, .5);
      await g.moveTo(at(board, .5, 3.5));
      await tester.pump();
      await g.up();
      expect(log, ['drag 0,0', 'drag 0,1', 'drag 0,2', 'drag 0,3']);
    });

    testWidgets('a wall in the jump stops it: the rest is dropped', (
      tester,
    ) async {
      final board = await pumpGrid(
        tester,
        puzzle: five.copyWith(walls: const [Wall(row: 0, col: 2)]),
      );
      final g = await begin(tester, board, .5, .5);
      await g.moveTo(at(board, .5, 3.5));
      await tester.pump();
      await g.up();
      expect(log, ['drag 0,0', 'drag 0,1']);
    });

    testWidgets('undo mid-gesture: the next move is judged on the new head', (
      tester,
    ) async {
      log = [];
      final engine = GameEngine(five);
      final empty = engine.createInitialState();
      final one = engine.addToPath(empty, 0, 0);
      Widget grid(GameState state) => buildTestWidgetInScaffold(
        PuzzleGrid(
          gameState: state,
          onCellTap: (r, c) => log.add('tap $r,$c'),
          onCellDrag: (r, c) => log.add('drag $r,$c'),
        ),
      );
      await tester.pumpWidget(grid(empty));
      final board = tester.getRect(
        find
            .descendant(
              of: find.byType(PuzzleGrid),
              matching: find.byType(CustomPaint),
            )
            .first,
      );
      final g = await begin(tester, board, .5, .5);
      await g.moveTo(at(board, .5, 1.5));
      expect(log, ['drag 0,0', 'drag 0,1']);
      // The undo button took the head back to (0,0).
      await tester.pumpWidget(grid(one));
      await g.moveTo(at(board, .5, 1.6)); // still inside (0,1)
      await tester.pump();
      await g.up();
      expect(log, ['drag 0,0', 'drag 0,1', 'drag 0,1']);
    });

    testWidgets('a tap after a drag uses the real state', (tester) async {
      final board = await pumpGrid(tester, puzzle: five);
      final g = await begin(tester, board, .5, .5);
      await g.moveTo(at(board, .5, 1.5));
      await g.up();
      await tester.pump();
      log.clear();
      // The frozen prop still has an empty path, so (0,2) is not a legal
      // first cell. A leftover pending head would accept it.
      await tester.tapAt(at(board, .5, 2.5));
      await tester.pump(const Duration(milliseconds: 400));
      expect(log, isEmpty);
    });

    testWidgets('one haptic per pointer event however many cells fill', (
      tester,
    ) async {
      var clicks = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate' &&
              call.arguments == 'HapticFeedbackType.selectionClick') {
            clicks++;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final board = await pumpGrid(tester, puzzle: five);
      final g = await begin(tester, board, .5, .5);
      await g.moveTo(at(board, .5, 3.5)); // three cells in one event
      await tester.pump();
      await g.up();
      expect(log.length, 4);
      expect(clicks, 2); // the press itself, then the one move event
    });
  });
  group('sliding over the existing line (5x5)', () {
    late Directory dir;
    setUp(() async => dir = await initTestStorage());
    tearDown(() async => dir.delete(recursive: true));

    const five = Puzzle(
      id: 'five',
      puzzleDate: '2026-10-06',
      gridSize: 5,
      waypoints: [
        Waypoint(order: 1, row: 0, col: 0),
        Waypoint(order: 2, row: 4, col: 4),
      ],
      walls: [],
      difficulty: 'easy',
      parTimeSeconds: 60,
    );

    late GameEngine engine;
    late GameState state;
    late int invalid;
    late int haptics;
    late int undosCharged;
    late bool dragCharged;

    List<String> pathOf() =>
        state.path.map((p) => '${p.row},${p.col}').toList();

    /// A grid fed by a live state, like the real screen: every drag or tap is
    /// applied through the engine and the grid rebuilds. Undo is charged once
    /// per gesture, as the provider does.
    Future<Rect> pumpLive(WidgetTester tester, List<(int, int)> initial) async {
      engine = GameEngine(five);
      state = engine.createInitialState();
      for (final (r, c) in initial) {
        state = engine.addToPath(state, r, c);
      }
      invalid = 0;
      haptics = 0;
      undosCharged = 0;
      dragCharged = false;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate') haptics++;
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      late StateSetter set;
      await tester.pumpWidget(
        buildTestWidgetInScaffold(
          StatefulBuilder(
            builder: (context, setState) {
              set = setState;
              return PuzzleGrid(
                gameState: state,
                onInvalidMove: (r, c) => invalid++,
                onCellTap: (r, c) => set(() {
                  state = engine.handleCellTap(state, r, c);
                }),
                onCellDrag: (r, c) => set(() {
                  final before = state.path.length;
                  state = engine.handleCellTap(
                    state,
                    r,
                    c,
                    countUndo: !dragCharged,
                  );
                  if (state.path.length < before && !dragCharged) {
                    dragCharged = true;
                    undosCharged++;
                  }
                }),
                onDragEnd: () => dragCharged = false,
              );
            },
          ),
        ),
      );
      return tester.getRect(
        find
            .descendant(
              of: find.byType(PuzzleGrid),
              matching: find.byType(CustomPaint),
            )
            .first,
      );
    }

    Offset cell(Rect board, int row, int col) {
      final c = board.width / 5;
      return board.topLeft + Offset(c * (col + .5), c * (row + .5));
    }

    // (0,0)(0,1)(0,2)(1,2)(1,1): the head (1,1) sits next to older (0,1).
    const doubled = [(0, 0), (0, 1), (0, 2), (1, 2), (1, 1)];

    testWidgets('sliding across an older filled cell leaves the line alone', (
      tester,
    ) async {
      final board = await pumpLive(tester, doubled);
      final before = pathOf();
      final g = await tester.startGesture(cell(board, 1, 1));
      final baseHaptics = haptics;
      await g.moveTo(cell(board, 0, 1)); // older cell, index 1
      await tester.pump();
      await g.up();
      await tester.pump(const Duration(milliseconds: 400));
      expect(pathOf(), before);
      expect(invalid, 0);
      expect(haptics, baseHaptics);
      expect(undosCharged, 0);
    });

    testWidgets('dragging back onto the cell before the head removes one', (
      tester,
    ) async {
      final board = await pumpLive(tester, doubled);
      final g = await tester.startGesture(cell(board, 1, 1));
      await g.moveTo(cell(board, 1, 2));
      await tester.pump();
      await g.up();
      expect(pathOf(), ['0,0', '0,1', '0,2', '1,2']);
      expect(invalid, 0);
    });

    testWidgets('a continuous backward sweep peels cells, one undo charged', (
      tester,
    ) async {
      final board = await pumpLive(tester, doubled);
      final g = await tester.startGesture(cell(board, 1, 1));
      await g.moveTo(cell(board, 1, 2));
      await tester.pump();
      await g.moveTo(cell(board, 0, 2));
      await tester.pump();
      await g.moveTo(cell(board, 0, 1));
      await tester.pump();
      await g.up();
      expect(pathOf(), ['0,0', '0,1']);
      expect(undosCharged, 1);
    });

    testWidgets('pressing straight on an earlier cell retracts to it', (
      tester,
    ) async {
      final board = await pumpLive(tester, doubled);
      final g = await tester.startGesture(cell(board, 0, 2));
      await tester.pump();
      await g.up();
      await tester.pump(const Duration(milliseconds: 400));
      expect(pathOf(), ['0,0', '0,1', '0,2']);
    });

    testWidgets('tapping an earlier cell retracts to it', (tester) async {
      final board = await pumpLive(tester, doubled);
      await tester.tapAt(cell(board, 0, 1));
      await tester.pump(const Duration(milliseconds: 400));
      expect(pathOf(), ['0,0', '0,1']);
    });

    testWidgets('a flick over an older cell then a far cell does nothing', (
      tester,
    ) async {
      // Head (1,2); (1,1) is older, (1,0) is empty but not adjacent to the head.
      final board = await pumpLive(tester, const [
        (0, 0),
        (0, 1),
        (1, 1),
        (2, 1),
        (2, 2),
        (1, 2),
      ]);
      final before = pathOf();
      final g = await tester.startGesture(cell(board, 1, 2));
      await g.moveTo(cell(board, 1, 0));
      await tester.pump();
      await g.up();
      await tester.pump(const Duration(milliseconds: 400));
      expect(pathOf(), before);
    });

    testWidgets('forward drawing is unchanged', (tester) async {
      final board = await pumpLive(tester, const [(0, 0)]);
      final g = await tester.startGesture(cell(board, 0, 0));
      await g.moveTo(cell(board, 0, 3));
      await tester.pump();
      await g.up();
      expect(pathOf(), ['0,0', '0,1', '0,2', '0,3']);
    });
  });
}
