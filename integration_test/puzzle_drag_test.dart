import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:zlynker/core/constants/app_colors.dart';
import 'package:zlynker/features/puzzle/domain/game_engine.dart';
import 'package:zlynker/features/puzzle/domain/models/game_state.dart';
import 'package:zlynker/features/puzzle/domain/models/puzzle.dart';
import 'package:zlynker/features/puzzle/presentation/widgets/puzzle_grid.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // 5x5 test puzzle — waypoints at (0,0) and (4,4), no walls
  const testPuzzle = Puzzle(
    id: 'integration-test-1',
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

  group('PuzzleGrid Drag Gestures', () {
    testWidgets('forward drag fires onCellDrag for adjacent cells',
        (tester) async {
      final engine = GameEngine(testPuzzle);
      var gameState = engine.createInitialState();

      // Start game by adding first waypoint
      gameState = engine.addToPath(gameState, 0, 0);
      gameState = gameState.copyWith(status: GameStatus.playing);

      final draggedCells = <String>[];

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: ThemeData.dark(),
            home: Scaffold(
              backgroundColor: AppColors.deepBlack,
              body: Center(
                child: SizedBox(
                  width: 375,
                  height: 375,
                  child: PuzzleGrid(
                    gameState: gameState,
                    onCellTap: (r, c) {},
                    onCellDrag: (r, c) => draggedCells.add('$r,$c'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await binding.convertFlutterSurfaceToImage();
      await tester.pumpAndSettle();
      await binding.takeScreenshot('01_initial_path_at_0_0');

      final gridBox = tester.getRect(find.byType(PuzzleGrid));
      final cellSize = gridBox.width / 5;

      // Drag from center of (0,0) down to center of (2,0)
      final start = Offset(
        gridBox.left + cellSize * 0.5,
        gridBox.top + cellSize * 0.5,
      );
      final offset = Offset(0, cellSize * 2);

      await tester.timedDragFrom(start, offset, const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(draggedCells, isNotEmpty,
          reason: 'Forward drag should fire onCellDrag callbacks');
    });

    testWidgets('backward drag fires onCellDrag for path cells',
        (tester) async {
      final engine = GameEngine(testPuzzle);
      var gameState = engine.createInitialState();

      // Build a path: (0,0) -> (0,1) -> (0,2) -> (0,3)
      gameState = engine.addToPath(gameState, 0, 0);
      gameState = gameState.copyWith(status: GameStatus.playing);
      gameState = engine.addToPath(gameState, 0, 1);
      gameState = engine.addToPath(gameState, 0, 2);
      gameState = engine.addToPath(gameState, 0, 3);
      expect(gameState.path.length, 4);

      final draggedCells = <String>[];

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: ThemeData.dark(),
            home: Scaffold(
              backgroundColor: AppColors.deepBlack,
              body: Center(
                child: SizedBox(
                  width: 375,
                  height: 375,
                  child: PuzzleGrid(
                    gameState: gameState,
                    onCellTap: (r, c) {},
                    onCellDrag: (r, c) => draggedCells.add('$r,$c'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await binding.convertFlutterSurfaceToImage();
      await tester.pumpAndSettle();
      await binding.takeScreenshot('02_path_0_0_to_0_3');

      final gridBox = tester.getRect(find.byType(PuzzleGrid));
      final cellSize = gridBox.width / 5;

      // Drag BACKWARD from (0,3) to (0,1)
      final start = Offset(
        gridBox.left + cellSize * 3.5,
        gridBox.top + cellSize * 0.5,
      );
      final offset = Offset(-cellSize * 2, 0);

      await tester.timedDragFrom(start, offset, const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(draggedCells, isNotEmpty,
          reason: 'Backward drag should fire onCellDrag callbacks');

      final hasBackwardCells =
          draggedCells.any((c) => c == '0,2' || c == '0,1');
      expect(hasBackwardCells, isTrue,
          reason: 'Backward drag should report cells already in path');
    });

    testWidgets('full backward-drag flow: path shrinks via engine',
        (tester) async {
      final engine = GameEngine(testPuzzle);
      var currentState = engine.createInitialState();
      currentState = engine.addToPath(currentState, 0, 0);
      currentState = currentState.copyWith(status: GameStatus.playing);
      currentState = engine.addToPath(currentState, 0, 1);
      currentState = engine.addToPath(currentState, 0, 2);
      currentState = engine.addToPath(currentState, 0, 3);
      currentState = engine.addToPath(currentState, 0, 4);
      expect(currentState.path.length, 5);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: ThemeData.dark(),
            home: StatefulBuilder(
              builder: (context, setState) {
                return Scaffold(
                  backgroundColor: AppColors.deepBlack,
                  body: Center(
                    child: SizedBox(
                      width: 375,
                      height: 375,
                      child: PuzzleGrid(
                        gameState: currentState,
                        onCellTap: (r, c) {
                          final newState =
                              engine.handleCellTap(currentState, r, c);
                          setState(() => currentState = newState);
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
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await binding.convertFlutterSurfaceToImage();
      await tester.pumpAndSettle();
      await binding.takeScreenshot('03_full_path_5_cells');

      final gridBox = tester.getRect(find.byType(PuzzleGrid));
      final cellSize = gridBox.width / 5;

      // Drag backward from (0,4) to (0,1) — should erase 3 cells
      final start = Offset(
        gridBox.left + cellSize * 4.5,
        gridBox.top + cellSize * 0.5,
      );
      final offset = Offset(-cellSize * 3, 0);

      await tester.timedDragFrom(
          start, offset, const Duration(milliseconds: 800));
      await tester.pumpAndSettle();

      await binding.takeScreenshot('04_after_backward_drag');

      expect(currentState.path.length, lessThan(5),
          reason:
              'Backward drag should have removed cells from path. '
              'Path length: ${currentState.path.length}, '
              'Path: ${currentState.path.map((p) => "(${p.row},${p.col})").join(" -> ")}');
    });

    testWidgets('tap on grid cell fires onCellTap', (tester) async {
      final engine = GameEngine(testPuzzle);
      final gameState = engine.createInitialState();

      final tappedCells = <String>[];

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: ThemeData.dark(),
            home: Scaffold(
              backgroundColor: AppColors.deepBlack,
              body: Center(
                child: SizedBox(
                  width: 375,
                  height: 375,
                  child: PuzzleGrid(
                    gameState: gameState,
                    onCellTap: (r, c) => tappedCells.add('$r,$c'),
                    onCellDrag: (r, c) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await binding.convertFlutterSurfaceToImage();
      await tester.pumpAndSettle();
      await binding.takeScreenshot('05_empty_grid_before_tap');

      final gridBox = tester.getRect(find.byType(PuzzleGrid));
      final cellSize = gridBox.width / 5;

      // Tap on (0,0) — first waypoint
      await tester.tapAt(Offset(
        gridBox.left + cellSize * 0.5,
        gridBox.top + cellSize * 0.5,
      ));
      await tester.pumpAndSettle();

      expect(tappedCells, contains('0,0'));
    });
  });
}
