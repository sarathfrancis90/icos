/// Full visual app test — renders the puzzle grid with a test puzzle,
/// simulates forward drawing + backward erasing, and takes screenshots
/// at each step for visual verification.
///
/// Run on simulator:
///   flutter test integration_test/visual_app_test.dart -d `<device_id>`
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icos/core/constants/app_colors.dart';
import 'package:icos/core/constants/app_sizes.dart';
import 'package:icos/features/puzzle/domain/game_engine.dart';
import 'package:icos/features/puzzle/domain/models/game_state.dart';
import 'package:icos/features/puzzle/domain/models/puzzle.dart';
import 'package:icos/features/puzzle/presentation/widgets/puzzle_grid.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const testPuzzle = Puzzle(
    id: 'visual-test-1',
    puzzleDate: '2026-01-01',
    gridSize: 5,
    waypoints: [
      Waypoint(order: 1, row: 0, col: 0),
      Waypoint(order: 2, row: 4, col: 4),
    ],
    walls: [],
    difficulty: 'easy',
    parTimeSeconds: 120,
  );

  /// Helper: find the CustomPaint inside PuzzleGrid which represents the
  /// actual grid area (excludes padding). This is where the GestureDetector
  /// for pan events lives and where cell coordinates are calculated from.
  Rect findGridRect(WidgetTester tester) {
    final customPaintFinder = find.descendant(
      of: find.byType(PuzzleGrid),
      matching: find.byType(CustomPaint),
    );
    return tester.getRect(customPaintFinder.first);
  }

  testWidgets('Visual: draw forward then erase backward via drag',
      (tester) async {
    final engine = GameEngine(testPuzzle);
    var currentState = engine.createInitialState();

    // Start the game at waypoint 1
    currentState = engine.addToPath(currentState, 0, 0);
    currentState = currentState.copyWith(status: GameStatus.playing);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(
            scaffoldBackgroundColor: AppColors.deepBlack,
          ),
          home: StatefulBuilder(
            builder: (context, setState) {
              return Scaffold(
                backgroundColor: AppColors.deepBlack,
                body: SafeArea(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(AppSizes.md),
                        child: Text(
                          'Path: ${currentState.path.length} cells  |  '
                          '${currentState.path.map((p) => "(${p.row},${p.col})").join(" → ")}',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 14),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      Expanded(
                        child: Center(
                          child: PuzzleGrid(
                            gameState: currentState,
                            onCellTap: (r, c) {
                              final newState =
                                  engine.handleCellTap(currentState, r, c);
                              setState(() => currentState =
                                  newState.copyWith(hintCell: null));
                            },
                            onCellDrag: (r, c) {
                              if (currentState.path.isNotEmpty &&
                                  currentState.path.last.row == r &&
                                  currentState.path.last.col == c) {
                                return;
                              }
                              final backtracked =
                                  engine.backtrackToCell(currentState, r, c);
                              if (backtracked != null) {
                                setState(() => currentState = backtracked);
                                return;
                              }
                              if (engine.canMoveToCell(currentState, r, c)) {
                                setState(() {
                                  currentState =
                                      engine.addToPath(currentState, r, c);
                                });
                              }
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // --- Screenshot 1: Initial state ---
    await binding.convertFlutterSurfaceToImage();
    await tester.pumpAndSettle();
    await binding.takeScreenshot('visual_01_initial');

    // Get the actual grid rect (the CustomPaint, not the padded PuzzleGrid)
    final gridRect = findGridRect(tester);
    final cellSize = gridRect.width / 5;

    // --- Step 1: Draw forward path along row 0 ---
    final startPos = Offset(
      gridRect.left + cellSize * 0.5,
      gridRect.top + cellSize * 0.5,
    );
    final forwardDrag = Offset(cellSize * 4, 0);

    await tester.timedDragFrom(
        startPos, forwardDrag, const Duration(milliseconds: 1000));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('visual_02_forward_drag');

    expect(currentState.path.length, greaterThanOrEqualTo(3),
        reason:
            'Forward drag should have added cells. '
            'Path: ${currentState.path.map((p) => "(${p.row},${p.col})").join(" → ")}');

    final pathLengthAfterForward = currentState.path.length;

    // --- Step 2: Drag BACKWARD from last cell toward start ---
    final lastCell = currentState.path.last;
    final targetCell = currentState.path[1];

    final backStart = Offset(
      gridRect.left + lastCell.col * cellSize + cellSize * 0.5,
      gridRect.top + lastCell.row * cellSize + cellSize * 0.5,
    );
    final backDrag = Offset(
      (targetCell.col - lastCell.col) * cellSize,
      (targetCell.row - lastCell.row) * cellSize,
    );

    await tester.timedDragFrom(
        backStart, backDrag, const Duration(milliseconds: 1000));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('visual_03_after_backward_drag');

    expect(currentState.path.length, lessThan(pathLengthAfterForward),
        reason:
            'Backward drag should have ERASED cells. '
            'Before: $pathLengthAfterForward, '
            'After: ${currentState.path.length}, '
            'Path: ${currentState.path.map((p) => "(${p.row},${p.col})").join(" → ")}');

    // --- Step 3: Continue forward to verify drag still works ---
    final restartCell = currentState.path.last;
    final restartPos = Offset(
      gridRect.left + restartCell.col * cellSize + cellSize * 0.5,
      gridRect.top + restartCell.row * cellSize + cellSize * 0.5,
    );

    await tester.timedDragFrom(
        restartPos, Offset(0, cellSize * 3), const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('visual_04_forward_after_backtrack');

    expect(currentState.path.length, greaterThan(1),
        reason: 'Forward drag after backtrack should work');
  });
}
