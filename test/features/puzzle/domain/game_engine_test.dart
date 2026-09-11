import 'package:flutter_test/flutter_test.dart';
import 'package:icos/features/puzzle/domain/game_engine.dart';
import 'package:icos/features/puzzle/domain/models/game_state.dart';
import 'package:icos/features/puzzle/domain/models/puzzle.dart';

void main() {
  group('retraction', _retractionTests);
  // Standard 3x3 test puzzle (no walls):
  //   (0,0)W1  (0,1)     (0,2)
  //   (1,0)    (1,1)     (1,2)
  //   (2,0)    (2,1)     (2,2)W2
  //
  // Solution path: (0,0)->(0,1)->(0,2)->(1,2)->(1,1)->(1,0)->(2,0)->(2,1)->(2,2)
  late Puzzle testPuzzle;
  late GameEngine engine;
  late GameState initialState;

  // 3x3 puzzle with a wall at (1,1) for wall-specific tests
  late Puzzle walledPuzzle;
  late GameEngine walledEngine;
  late GameState walledInitialState;

  setUp(() {
    testPuzzle = const Puzzle(
      id: 'test-puzzle-1',
      puzzleDate: '2026-03-03',
      gridSize: 3,
      waypoints: [
        Waypoint(order: 1, row: 0, col: 0),
        Waypoint(order: 2, row: 2, col: 2),
      ],
      walls: [],
      difficulty: 'easy',
      parTimeSeconds: 60,
    );
    engine = GameEngine(testPuzzle);
    initialState = engine.createInitialState();

    walledPuzzle = const Puzzle(
      id: 'test-walled-1',
      puzzleDate: '2026-03-03',
      gridSize: 3,
      waypoints: [
        Waypoint(order: 1, row: 0, col: 0),
        Waypoint(order: 2, row: 2, col: 2),
      ],
      walls: [Wall(row: 1, col: 1)],
      difficulty: 'easy',
      parTimeSeconds: 60,
    );
    walledEngine = GameEngine(walledPuzzle);
    walledInitialState = walledEngine.createInitialState();
  });

  group('createInitialState', () {
    test('creates grid with correct dimensions', () {
      expect(initialState.grid.length, 3);
      for (final row in initialState.grid) {
        expect(row.length, 3);
      }
    });

    test('places walls correctly as CellState.wall', () {
      expect(walledInitialState.grid[1][1], CellState.wall);
    });

    test('places waypoints correctly as CellState.waypoint', () {
      expect(initialState.grid[0][0], CellState.waypoint);
      expect(initialState.grid[2][2], CellState.waypoint);
    });

    test('leaves other cells as CellState.empty', () {
      expect(initialState.grid[0][1], CellState.empty);
      expect(initialState.grid[0][2], CellState.empty);
      expect(initialState.grid[1][0], CellState.empty);
      expect(initialState.grid[1][1], CellState.empty);
      expect(initialState.grid[1][2], CellState.empty);
      expect(initialState.grid[2][0], CellState.empty);
      expect(initialState.grid[2][1], CellState.empty);
    });

    test('leaves non-wall non-waypoint cells empty in walled puzzle', () {
      expect(walledInitialState.grid[0][1], CellState.empty);
      expect(walledInitialState.grid[0][2], CellState.empty);
      expect(walledInitialState.grid[1][0], CellState.empty);
      expect(walledInitialState.grid[1][2], CellState.empty);
      expect(walledInitialState.grid[2][0], CellState.empty);
      expect(walledInitialState.grid[2][1], CellState.empty);
    });

    test('initializes with empty path', () {
      expect(initialState.path, isEmpty);
    });

    test('sets status to notStarted', () {
      expect(initialState.status, GameStatus.notStarted);
    });

    test('initializes currentWaypointIndex to 0', () {
      expect(initialState.currentWaypointIndex, 0);
    });

    test('initializes counters to 0', () {
      expect(initialState.elapsedSeconds, 0);
      expect(initialState.hintsUsed, 0);
      expect(initialState.undosUsed, 0);
    });

    test('stores puzzle reference', () {
      expect(initialState.puzzle, testPuzzle);
    });
  });

  group('canMoveToCell', () {
    test('returns false for out-of-bounds negative row', () {
      expect(engine.canMoveToCell(initialState, -1, 0), isFalse);
    });

    test('returns false for out-of-bounds negative col', () {
      expect(engine.canMoveToCell(initialState, 0, -1), isFalse);
    });

    test('returns false for out-of-bounds row beyond grid', () {
      expect(engine.canMoveToCell(initialState, 3, 0), isFalse);
    });

    test('returns false for out-of-bounds col beyond grid', () {
      expect(engine.canMoveToCell(initialState, 0, 3), isFalse);
    });

    test('returns false for wall cells', () {
      expect(walledEngine.canMoveToCell(walledInitialState, 1, 1), isFalse);
    });

    test('first move must be at first waypoint', () {
      expect(engine.canMoveToCell(initialState, 0, 0), isTrue);
    });

    test('first move at non-waypoint cell returns false', () {
      expect(engine.canMoveToCell(initialState, 0, 1), isFalse);
      expect(engine.canMoveToCell(initialState, 1, 0), isFalse);
      expect(engine.canMoveToCell(initialState, 2, 2), isFalse);
    });

    test('returns false for non-adjacent cells', () {
      final state = engine.addToPath(initialState, 0, 0);
      // (2,2) is not adjacent to (0,0)
      expect(engine.canMoveToCell(state, 2, 2), isFalse);
      // (0,2) is not adjacent to (0,0) - distance 2
      expect(engine.canMoveToCell(state, 0, 2), isFalse);
    });

    test('returns false for cells already in path', () {
      var state = engine.addToPath(initialState, 0, 0);
      state = engine.addToPath(state, 0, 1);
      // (0,0) is already in path
      expect(engine.canMoveToCell(state, 0, 0), isFalse);
    });

    test('returns false for diagonal cells (non-adjacent)', () {
      var state = engine.addToPath(initialState, 0, 0);
      state = engine.addToPath(state, 0, 1);
      // From (0,1), (1,0) is diagonal - Manhattan distance is 2, not 1
      expect(engine.canMoveToCell(state, 1, 0), isFalse);
    });

    test('waypoints must be visited in order - wrong order returns false', () {
      // Use a 3-waypoint puzzle to properly test out-of-order waypoint access
      final threeWpPuzzle = const Puzzle(
        id: 'test-3wp',
        puzzleDate: '2026-03-03',
        gridSize: 3,
        waypoints: [
          Waypoint(order: 1, row: 0, col: 0),
          Waypoint(order: 2, row: 0, col: 2),
          Waypoint(order: 3, row: 2, col: 2),
        ],
        walls: [Wall(row: 1, col: 1)],
        difficulty: 'easy',
        parTimeSeconds: 60,
      );
      final eng3 = GameEngine(threeWpPuzzle);
      var s = eng3.createInitialState();

      // Visit waypoint 1 at (0,0)
      s = eng3.addToPath(s, 0, 0);
      // Move to (1,0)
      s = eng3.addToPath(s, 1, 0);
      // Move to (2,0)
      s = eng3.addToPath(s, 2, 0);
      // Move to (2,1)
      s = eng3.addToPath(s, 2, 1);
      // Now at (2,1), adjacent to (2,2) which is waypoint 3 (order=3).
      // currentWaypointIndex is 0 (only waypoint 1 visited).
      // Expected next waypoint order = currentWaypointIndex(0) + 2 = 2
      // waypoint 3 has order=3, which does not equal 2 -> returns false.
      expect(eng3.canMoveToCell(s, 2, 2), isFalse);
    });

    test('waypoints must be visited in correct order returns true', () {
      // Path: (0,0) -> (0,1) -> (0,2) -> (1,2)
      var state = engine.addToPath(initialState, 0, 0);
      state = engine.addToPath(state, 0, 1);
      state = engine.addToPath(state, 0, 2);
      state = engine.addToPath(state, 1, 2);
      // From (1,2), (2,2) is adjacent and is waypoint 2 (order=2).
      // currentWaypointIndex = 0 (waypoint 1 visited), expected = 0 + 2 = 2
      // waypoint 2 order = 2 -> matches.
      expect(engine.canMoveToCell(state, 2, 2), isTrue);
    });

    test('returns true for valid adjacent empty cell', () {
      final state = engine.addToPath(initialState, 0, 0);
      // (0,1) is adjacent and empty
      expect(engine.canMoveToCell(state, 0, 1), isTrue);
      // (1,0) is adjacent and empty
      expect(engine.canMoveToCell(state, 1, 0), isTrue);
    });

    test('wall is still blocked even when adjacent to path', () {
      var state = walledEngine.addToPath(walledInitialState, 0, 0);
      state = walledEngine.addToPath(state, 0, 1);
      // (1,1) is adjacent to (0,1) but is a wall
      expect(walledEngine.canMoveToCell(state, 1, 1), isFalse);
    });
  });

  group('addToPath', () {
    test('adds cell to path', () {
      final state = engine.addToPath(initialState, 0, 0);
      expect(state.path.length, 1);
      expect(state.path.first.row, 0);
      expect(state.path.first.col, 0);
    });

    test('adds multiple cells to path sequentially', () {
      var state = engine.addToPath(initialState, 0, 0);
      state = engine.addToPath(state, 0, 1);
      expect(state.path.length, 2);
      expect(state.path[1].row, 0);
      expect(state.path[1].col, 1);
    });

    test('updates grid cell state to filled for empty cells', () {
      var state = engine.addToPath(initialState, 0, 0);
      state = engine.addToPath(state, 0, 1);
      // (0,1) was empty, should now be filled
      expect(state.grid[0][1], CellState.filled);
    });

    test('keeps waypoint cell state as waypoint', () {
      final state = engine.addToPath(initialState, 0, 0);
      // (0,0) is a waypoint, should remain waypoint
      expect(state.grid[0][0], CellState.waypoint);
    });

    test('updates currentWaypointIndex when visiting waypoint 1', () {
      var state = engine.addToPath(initialState, 0, 0);
      // After visiting waypoint 1 (order=1), currentWaypointIndex = order - 1 = 0
      expect(state.currentWaypointIndex, 0);
    });

    test('updates currentWaypointIndex when visiting waypoint 2', () {
      // Navigate to waypoint 2 at (2,2)
      var state = engine.addToPath(initialState, 0, 0);
      state = engine.addToPath(state, 0, 1);
      state = engine.addToPath(state, 0, 2);
      state = engine.addToPath(state, 1, 2);
      expect(engine.canMoveToCell(state, 2, 2), isTrue);
      state = engine.addToPath(state, 2, 2);
      // After visiting waypoint 2 (order=2), currentWaypointIndex = order - 1 = 1
      expect(state.currentWaypointIndex, 1);
    });

    test('changes status from notStarted to playing', () {
      expect(initialState.status, GameStatus.notStarted);
      final state = engine.addToPath(initialState, 0, 0);
      expect(state.status, GameStatus.playing);
    });

    test('keeps playing status when already playing', () {
      var state = engine.addToPath(initialState, 0, 0);
      expect(state.status, GameStatus.playing);
      state = engine.addToPath(state, 0, 1);
      expect(state.status, GameStatus.playing);
    });

    test('returns unchanged state for invalid moves', () {
      // Try to move to a non-starting cell
      final state = engine.addToPath(initialState, 0, 1);
      expect(identical(state, initialState), isTrue);
    });

    test('returns unchanged state when moving to wall', () {
      final state = walledEngine.addToPath(walledInitialState, 1, 1);
      expect(identical(state, walledInitialState), isTrue);
    });

    test('returns unchanged state when moving out of bounds', () {
      final state = engine.addToPath(initialState, -1, 0);
      expect(identical(state, initialState), isTrue);
    });

    test('does not modify original grid (immutability)', () {
      final originalGrid00 = initialState.grid[0][0];
      engine.addToPath(initialState, 0, 0);
      // Original state grid should be unchanged
      expect(initialState.grid[0][0], originalGrid00);
    });

    test('does not change currentWaypointIndex for non-waypoint cells', () {
      var state = engine.addToPath(initialState, 0, 0);
      expect(state.currentWaypointIndex, 0);
      state = engine.addToPath(state, 0, 1);
      // (0,1) is not a waypoint, index stays the same
      expect(state.currentWaypointIndex, 0);
    });
  });

  group('undo', () {
    test('removes last cell from path', () {
      var state = engine.addToPath(initialState, 0, 0);
      state = engine.addToPath(state, 0, 1);
      expect(state.path.length, 2);

      state = engine.undo(state);
      expect(state.path.length, 1);
      expect(state.path.last.row, 0);
      expect(state.path.last.col, 0);
    });

    test('restores cell state to empty for regular cells', () {
      var state = engine.addToPath(initialState, 0, 0);
      state = engine.addToPath(state, 0, 1);
      expect(state.grid[0][1], CellState.filled);

      state = engine.undo(state);
      expect(state.grid[0][1], CellState.empty);
    });

    test('restores cell state to waypoint for waypoint cells', () {
      var state = engine.addToPath(initialState, 0, 0);
      state = engine.addToPath(state, 0, 1);
      state = engine.addToPath(state, 0, 2);
      state = engine.addToPath(state, 1, 2);
      state = engine.addToPath(state, 2, 2);
      // (2,2) is waypoint, grid should show waypoint
      expect(state.grid[2][2], CellState.waypoint);

      state = engine.undo(state);
      // After undo, (2,2) should be restored to waypoint (it was a waypoint cell)
      expect(state.grid[2][2], CellState.waypoint);
    });

    test('recalculates currentWaypointIndex after undo', () {
      var state = engine.addToPath(initialState, 0, 0);
      state = engine.addToPath(state, 0, 1);
      state = engine.addToPath(state, 0, 2);
      state = engine.addToPath(state, 1, 2);
      state = engine.addToPath(state, 2, 2);
      expect(state.currentWaypointIndex, 1); // visited waypoint 2

      state = engine.undo(state); // remove (2,2) - waypoint 2
      // Only waypoint 1 at (0,0) remains in path
      expect(state.currentWaypointIndex, 0);
    });

    test('increments undosUsed', () {
      var state = engine.addToPath(initialState, 0, 0);
      expect(state.undosUsed, 0);

      state = engine.undo(state);
      expect(state.undosUsed, 1);
    });

    test('increments undosUsed cumulatively', () {
      var state = engine.addToPath(initialState, 0, 0);
      state = engine.addToPath(state, 0, 1);

      state = engine.undo(state);
      expect(state.undosUsed, 1);

      state = engine.undo(state);
      expect(state.undosUsed, 2);
    });

    test('returns unchanged state for empty path', () {
      final state = engine.undo(initialState);
      expect(identical(state, initialState), isTrue);
    });

    test('undo of first move results in empty path', () {
      var state = engine.addToPath(initialState, 0, 0);
      state = engine.undo(state);
      expect(state.path, isEmpty);
    });

    test('currentWaypointIndex returns to 0 when all waypoints undone', () {
      var state = engine.addToPath(initialState, 0, 0);
      state = engine.undo(state);
      expect(state.currentWaypointIndex, 0);
    });
  });

  group('reset', () {
    test('returns to initial grid state', () {
      var state = engine.addToPath(initialState, 0, 0);
      state = engine.addToPath(state, 0, 1);
      state = engine.addToPath(state, 0, 2);

      final resetState = engine.reset(state);
      // Grid should be back to initial layout
      expect(resetState.grid[0][0], CellState.waypoint);
      expect(resetState.grid[0][1], CellState.empty);
      expect(resetState.grid[0][2], CellState.empty);
      expect(resetState.grid[1][1], CellState.empty);
      expect(resetState.grid[2][2], CellState.waypoint);
    });

    test('returns to initial grid state for walled puzzle', () {
      var state = walledEngine.addToPath(walledInitialState, 0, 0);
      state = walledEngine.addToPath(state, 0, 1);

      final resetState = walledEngine.reset(state);
      expect(resetState.grid[0][0], CellState.waypoint);
      expect(resetState.grid[0][1], CellState.empty);
      expect(resetState.grid[1][1], CellState.wall);
      expect(resetState.grid[2][2], CellState.waypoint);
    });

    test('clears the path', () {
      var state = engine.addToPath(initialState, 0, 0);
      state = engine.addToPath(state, 0, 1);

      final resetState = engine.reset(state);
      expect(resetState.path, isEmpty);
    });

    test('preserves elapsedSeconds', () {
      var state = engine.addToPath(initialState, 0, 0);
      state = state.copyWith(elapsedSeconds: 42);

      final resetState = engine.reset(state);
      expect(resetState.elapsedSeconds, 42);
    });

    test('preserves hintsUsed', () {
      var state = engine.addToPath(initialState, 0, 0);
      state = state.copyWith(hintsUsed: 3);

      final resetState = engine.reset(state);
      expect(resetState.hintsUsed, 3);
    });

    test('preserves undosUsed', () {
      var state = engine.addToPath(initialState, 0, 0);
      state = state.copyWith(undosUsed: 5);

      final resetState = engine.reset(state);
      expect(resetState.undosUsed, 5);
    });

    test('sets status to playing', () {
      final resetState = engine.reset(initialState);
      expect(resetState.status, GameStatus.playing);
    });

    test('resets currentWaypointIndex to 0', () {
      var state = engine.addToPath(initialState, 0, 0);
      state = engine.addToPath(state, 0, 1);
      state = engine.addToPath(state, 0, 2);
      state = engine.addToPath(state, 1, 2);
      state = engine.addToPath(state, 2, 2);
      expect(state.currentWaypointIndex, 1);

      final resetState = engine.reset(state);
      expect(resetState.currentWaypointIndex, 0);
    });
  });

  group('isSolved', () {
    test('returns false when not all waypoints visited', () {
      // Only visit waypoint 1
      final state = engine.addToPath(initialState, 0, 0);
      expect(engine.isSolved(state), isFalse);
    });

    test('returns false when path is empty', () {
      expect(engine.isSolved(initialState), isFalse);
    });

    test('returns false when path does not end at last waypoint', () {
      // Build a path that visits both waypoints but does not end at the last one.
      // Visit waypoint 2, then continue past it.
      var state = engine.addToPath(initialState, 0, 0);
      state = engine.addToPath(state, 0, 1);
      state = engine.addToPath(state, 0, 2);
      state = engine.addToPath(state, 1, 2);
      state = engine.addToPath(state, 2, 2);
      // Now path ends at waypoint 2, but we continue...
      state = engine.addToPath(state, 2, 1);
      // Now path ends at (2,1), not at waypoint 2
      expect(state.currentWaypointIndex, 1);
      expect(engine.isSolved(state), isFalse);
    });

    test('returns false when not all cells filled', () {
      // Visit waypoints in order but don't fill all cells
      var state = engine.addToPath(initialState, 0, 0);
      state = engine.addToPath(state, 0, 1);
      state = engine.addToPath(state, 0, 2);
      state = engine.addToPath(state, 1, 2);
      state = engine.addToPath(state, 2, 2);
      // Path has 5 cells, but 9 non-wall cells exist -> not solved
      expect(engine.isSolved(state), isFalse);
    });

    test('returns true when all conditions met (complete Hamiltonian path)', () {
      // Solution: (0,0)->(0,1)->(0,2)->(1,2)->(1,1)->(1,0)->(2,0)->(2,1)->(2,2)
      var state = engine.addToPath(initialState, 0, 0);
      state = engine.addToPath(state, 0, 1);
      state = engine.addToPath(state, 0, 2);
      state = engine.addToPath(state, 1, 2);
      state = engine.addToPath(state, 1, 1);
      state = engine.addToPath(state, 1, 0);
      state = engine.addToPath(state, 2, 0);
      state = engine.addToPath(state, 2, 1);
      state = engine.addToPath(state, 2, 2);

      expect(state.path.length, 9);
      expect(state.currentWaypointIndex, 1);
      expect(engine.isSolved(state), isTrue);
    });

    test('returns false with correct path length but wrong endpoint', () {
      // Manually construct a state where all conditions are met except endpoint
      final manualState = initialState.copyWith(
        currentWaypointIndex: 1,
        path: [
          const GridPosition(row: 0, col: 0),
          const GridPosition(row: 0, col: 1),
          const GridPosition(row: 0, col: 2),
          const GridPosition(row: 1, col: 2),
          const GridPosition(row: 2, col: 2),
          const GridPosition(row: 2, col: 1),
          const GridPosition(row: 2, col: 0),
          const GridPosition(row: 1, col: 0),
          const GridPosition(row: 1, col: 1), // ends at (1,1), not (2,2)
        ],
      );
      expect(engine.isSolved(manualState), isFalse);
    });
  });

  group('handleCellTap', () {
    test('tapping second-to-last cell triggers undo (backtracking)', () {
      var state = engine.addToPath(initialState, 0, 0);
      state = engine.addToPath(state, 0, 1);
      expect(state.path.length, 2);

      // Tap (0,0) which is the second-to-last cell
      state = engine.handleCellTap(state, 0, 0);
      expect(state.path.length, 1);
      expect(state.path.last.row, 0);
      expect(state.path.last.col, 0);
      // undo increments undosUsed
      expect(state.undosUsed, 1);
    });

    test('tapping valid adjacent cell adds to path', () {
      var state = engine.addToPath(initialState, 0, 0);
      // Tap (0,1) which is valid and adjacent
      state = engine.handleCellTap(state, 0, 1);
      expect(state.path.length, 2);
      expect(state.path.last.row, 0);
      expect(state.path.last.col, 1);
    });

    test('tapping invalid cell returns unchanged state', () {
      var state = engine.addToPath(initialState, 0, 0);
      // Tap (2,2) which is not adjacent
      final newState = engine.handleCellTap(state, 2, 2);
      expect(identical(newState, state), isTrue);
    });

    test('tapping wall returns unchanged state', () {
      var state = walledEngine.addToPath(walledInitialState, 0, 0);
      final newState = walledEngine.handleCellTap(state, 1, 1);
      expect(identical(newState, state), isTrue);
    });

    test('tapping first waypoint on empty path starts the game', () {
      final state = engine.handleCellTap(initialState, 0, 0);
      expect(state.path.length, 1);
      expect(state.status, GameStatus.playing);
    });

    test('backtracking restores grid state correctly', () {
      var state = engine.addToPath(initialState, 0, 0);
      state = engine.addToPath(state, 0, 1);
      state = engine.addToPath(state, 0, 2);
      expect(state.grid[0][2], CellState.filled);

      // Tap (0,1) - the second-to-last - to backtrack
      state = engine.handleCellTap(state, 0, 1);
      expect(state.path.length, 2);
      expect(state.grid[0][2], CellState.empty);
    });

    test('does not trigger undo when path has only one cell', () {
      var state = engine.addToPath(initialState, 0, 0);
      // There is no second-to-last cell, so tapping any cell should try addToPath
      // Tap (0,1) - should add to path, not undo
      state = engine.handleCellTap(state, 0, 1);
      expect(state.path.length, 2);
    });

    test('handles tap on second-to-last with three cells in path', () {
      var state = engine.addToPath(initialState, 0, 0);
      state = engine.addToPath(state, 0, 1);
      state = engine.addToPath(state, 0, 2);
      expect(state.path.length, 3);

      // Tap (0,1) - the second-to-last
      state = engine.handleCellTap(state, 0, 1);
      expect(state.path.length, 2);
      expect(state.path.last.row, 0);
      expect(state.path.last.col, 1);
    });
  });

  group('backtrackToCell', () {
    test('returns null when cell is not in path', () {
      var state = engine.addToPath(initialState, 0, 0);
      state = engine.addToPath(state, 0, 1);
      state = engine.addToPath(state, 0, 2);

      final result = engine.backtrackToCell(state, 2, 2);
      expect(result, isNull);
    });

    test('returns null when cell is the last cell in path', () {
      var state = engine.addToPath(initialState, 0, 0);
      state = engine.addToPath(state, 0, 1);
      state = engine.addToPath(state, 0, 2);

      final result = engine.backtrackToCell(state, 0, 2);
      expect(result, isNull);
    });

    test('backtracks to second-to-last cell (removes last)', () {
      var state = engine.addToPath(initialState, 0, 0);
      state = engine.addToPath(state, 0, 1);
      state = engine.addToPath(state, 0, 2);

      final result = engine.backtrackToCell(state, 0, 1)!;
      expect(result.path.length, 2);
      expect(result.path.last.row, 0);
      expect(result.path.last.col, 1);
      // Removed cell should be restored to empty
      expect(result.grid[0][2], CellState.empty);
    });

    test('backtracks multiple cells at once', () {
      var state = engine.addToPath(initialState, 0, 0);
      state = engine.addToPath(state, 0, 1);
      state = engine.addToPath(state, 0, 2);
      state = engine.addToPath(state, 1, 2);
      state = engine.addToPath(state, 1, 1);
      expect(state.path.length, 5);

      // Backtrack to (0,1) — should remove (0,2), (1,2), (1,1)
      final result = engine.backtrackToCell(state, 0, 1)!;
      expect(result.path.length, 2);
      expect(result.path.last.col, 1);
      expect(result.grid[0][2], CellState.empty);
      expect(result.grid[1][2], CellState.empty);
      expect(result.grid[1][1], CellState.empty);
    });

    test('backtracks to first cell (removes all but first)', () {
      var state = engine.addToPath(initialState, 0, 0);
      state = engine.addToPath(state, 0, 1);
      state = engine.addToPath(state, 0, 2);

      final result = engine.backtrackToCell(state, 0, 0)!;
      expect(result.path.length, 1);
      expect(result.path.first.row, 0);
      expect(result.path.first.col, 0);
    });

    test('restores waypoint cell state when backtracking over waypoint', () {
      // Build a path that goes through waypoint 2 at (2,2) and past it
      var state = engine.addToPath(initialState, 0, 0);
      state = engine.addToPath(state, 0, 1);
      state = engine.addToPath(state, 0, 2);
      state = engine.addToPath(state, 1, 2);
      state = engine.addToPath(state, 2, 2); // waypoint 2
      state = engine.addToPath(state, 2, 1);
      expect(state.currentWaypointIndex, 1);

      // Backtrack to (1,2) — removes (2,2) waypoint and (2,1)
      final result = engine.backtrackToCell(state, 1, 2)!;
      expect(result.grid[2][2], CellState.waypoint); // restored
      expect(result.grid[2][1], CellState.empty);
      expect(result.currentWaypointIndex, 0); // waypoint 2 no longer visited
    });

    test('recalculates waypoint index correctly after multi-cell backtrack', () {
      var state = engine.addToPath(initialState, 0, 0);
      state = engine.addToPath(state, 0, 1);
      state = engine.addToPath(state, 0, 2);
      state = engine.addToPath(state, 1, 2);
      state = engine.addToPath(state, 2, 2); // waypoint 2
      expect(state.currentWaypointIndex, 1);

      // Backtrack to (0,0) — should reset waypoint index to 0 (only wp1 visited)
      final result = engine.backtrackToCell(state, 0, 0)!;
      expect(result.path.length, 1);
      expect(result.currentWaypointIndex, 0);
    });

    test('does not modify the original state', () {
      var state = engine.addToPath(initialState, 0, 0);
      state = engine.addToPath(state, 0, 1);
      state = engine.addToPath(state, 0, 2);
      final originalPathLength = state.path.length;

      engine.backtrackToCell(state, 0, 1);
      expect(state.path.length, originalPathLength); // unchanged
    });
  });

  group('full solution walkthrough', () {
    test('complete solution path solves the puzzle via handleCellTap', () {
      // Solution: (0,0)->(0,1)->(0,2)->(1,2)->(1,1)->(1,0)->(2,0)->(2,1)->(2,2)
      var state = initialState;

      state = engine.handleCellTap(state, 0, 0);
      expect(state.status, GameStatus.playing);

      state = engine.handleCellTap(state, 0, 1);
      state = engine.handleCellTap(state, 0, 2);
      state = engine.handleCellTap(state, 1, 2);
      state = engine.handleCellTap(state, 1, 1);
      state = engine.handleCellTap(state, 1, 0);
      state = engine.handleCellTap(state, 2, 0);
      state = engine.handleCellTap(state, 2, 1);
      state = engine.handleCellTap(state, 2, 2);

      expect(engine.isSolved(state), isTrue);
      expect(state.path.length, 9);
    });

    test('solution with backtracking and redo', () {
      var state = engine.addToPath(initialState, 0, 0);
      state = engine.addToPath(state, 0, 1);
      state = engine.addToPath(state, 0, 2);

      // Backtrack from (0,2) by tapping (0,1)
      state = engine.handleCellTap(state, 0, 1);
      expect(state.path.length, 2);
      expect(state.undosUsed, 1);

      // Re-add (0,2) and complete the solution
      state = engine.addToPath(state, 0, 2);
      state = engine.addToPath(state, 1, 2);
      state = engine.addToPath(state, 1, 1);
      state = engine.addToPath(state, 1, 0);
      state = engine.addToPath(state, 2, 0);
      state = engine.addToPath(state, 2, 1);
      state = engine.addToPath(state, 2, 2);

      expect(engine.isSolved(state), isTrue);
      expect(state.undosUsed, 1);
    });

    test('complete solution then reset and re-solve', () {
      // Solve
      var state = engine.addToPath(initialState, 0, 0);
      state = engine.addToPath(state, 0, 1);
      state = engine.addToPath(state, 0, 2);
      state = engine.addToPath(state, 1, 2);
      state = engine.addToPath(state, 1, 1);
      state = engine.addToPath(state, 1, 0);
      state = engine.addToPath(state, 2, 0);
      state = engine.addToPath(state, 2, 1);
      state = engine.addToPath(state, 2, 2);
      expect(engine.isSolved(state), isTrue);

      // Reset
      state = engine.reset(state);
      expect(engine.isSolved(state), isFalse);
      expect(state.path, isEmpty);
      expect(state.status, GameStatus.playing);

      // Re-solve
      state = engine.addToPath(state, 0, 0);
      state = engine.addToPath(state, 0, 1);
      state = engine.addToPath(state, 0, 2);
      state = engine.addToPath(state, 1, 2);
      state = engine.addToPath(state, 1, 1);
      state = engine.addToPath(state, 1, 0);
      state = engine.addToPath(state, 2, 0);
      state = engine.addToPath(state, 2, 1);
      state = engine.addToPath(state, 2, 2);
      expect(engine.isSolved(state), isTrue);
    });
  });

  group('edge cases', () {
    test('1x1 grid with single waypoint', () {
      const tinyPuzzle = Puzzle(
        id: 'tiny',
        puzzleDate: '2026-03-03',
        gridSize: 1,
        waypoints: [Waypoint(order: 1, row: 0, col: 0)],
        walls: [],
        difficulty: 'easy',
        parTimeSeconds: 10,
      );
      final tinyEngine = GameEngine(tinyPuzzle);
      var state = tinyEngine.createInitialState();

      state = tinyEngine.addToPath(state, 0, 0);
      expect(tinyEngine.isSolved(state), isTrue);
    });

    test('2x2 grid incomplete path is not solved', () {
      const smallPuzzle = Puzzle(
        id: 'small',
        puzzleDate: '2026-03-03',
        gridSize: 2,
        waypoints: [
          Waypoint(order: 1, row: 0, col: 0),
          Waypoint(order: 2, row: 1, col: 1),
        ],
        walls: [],
        difficulty: 'easy',
        parTimeSeconds: 30,
      );
      final smallEngine = GameEngine(smallPuzzle);
      var state = smallEngine.createInitialState();

      // Path: (0,0) -> (0,1) -> (1,1) -- only 3 cells, need 4
      state = smallEngine.addToPath(state, 0, 0);
      state = smallEngine.addToPath(state, 0, 1);
      state = smallEngine.addToPath(state, 1, 1);
      expect(smallEngine.isSolved(state), isFalse);
    });

    test('cannot move to same cell as current position', () {
      var state = engine.addToPath(initialState, 0, 0);
      // Try to add (0,0) again - it's already in path
      expect(engine.canMoveToCell(state, 0, 0), isFalse);
    });

    test('multiple walls block paths correctly', () {
      const multiWallPuzzle = Puzzle(
        id: 'multi-wall',
        puzzleDate: '2026-03-03',
        gridSize: 3,
        waypoints: [
          Waypoint(order: 1, row: 0, col: 0),
          Waypoint(order: 2, row: 2, col: 2),
        ],
        walls: [Wall(row: 0, col: 1), Wall(row: 1, col: 1)],
        difficulty: 'medium',
        parTimeSeconds: 60,
      );
      final multiWallEngine = GameEngine(multiWallPuzzle);
      final state = multiWallEngine.createInitialState();

      expect(state.grid[0][1], CellState.wall);
      expect(state.grid[1][1], CellState.wall);

      var s = multiWallEngine.addToPath(state, 0, 0);
      // From (0,0), cannot go to (0,1) because it's a wall
      expect(multiWallEngine.canMoveToCell(s, 0, 1), isFalse);
      // Can go to (1,0) which is empty
      expect(multiWallEngine.canMoveToCell(s, 1, 0), isTrue);
    });

    test('path builds correctly through narrow corridor around wall', () {
      // Using walledPuzzle (wall at 1,1), verify path around the wall
      var state = walledEngine.addToPath(walledInitialState, 0, 0);
      state = walledEngine.addToPath(state, 0, 1);
      state = walledEngine.addToPath(state, 0, 2);
      state = walledEngine.addToPath(state, 1, 2);
      // Verify the path is correct so far
      expect(state.path.length, 4);
      expect(state.grid[0][1], CellState.filled);
      expect(state.grid[0][2], CellState.filled);
      expect(state.grid[1][2], CellState.filled);
      expect(state.grid[1][1], CellState.wall); // wall unchanged
    });

    test('grid dimensions match for various sizes', () {
      for (final size in [1, 2, 4, 5]) {
        final puzzle = Puzzle(
          id: 'size-$size',
          puzzleDate: '2026-03-03',
          gridSize: size,
          waypoints: [Waypoint(order: 1, row: 0, col: 0)],
          walls: const [],
          difficulty: 'easy',
          parTimeSeconds: 60,
        );
        final eng = GameEngine(puzzle);
        final st = eng.createInitialState();
        expect(st.grid.length, size);
        for (final row in st.grid) {
          expect(row.length, size);
        }
      }
    });
  });
}

/// Retraction: tapping or dragging onto a cell already on the line pulls the
/// head back to it. See docs/superpowers/specs/2026-09-11-line-redesign-spec.md
void _retractionTests() {
  late Puzzle puzzle;
  late GameEngine engine;
  late GameState state;

  setUp(() {
    puzzle = const Puzzle(
      id: 'retract',
      puzzleDate: '2026-09-11',
      gridSize: 3,
      waypoints: [
        Waypoint(order: 1, row: 0, col: 0),
        Waypoint(order: 2, row: 2, col: 2),
      ],
      walls: [],
      difficulty: 'easy',
      parTimeSeconds: 60,
    );
    engine = GameEngine(puzzle);
    // Build (0,0)->(0,1)->(0,2)->(1,2)
    state = engine.createInitialState();
    for (final cell in const [
      [0, 0],
      [0, 1],
      [0, 2],
      [1, 2],
    ]) {
      state = engine.addToPath(state, cell[0], cell[1]);
    }
  });

  test('tapping a body cell retracts the line to it', () {
    final result = engine.handleCellTap(state, 0, 1);

    expect(result.path.length, 2);
    expect(result.path.last, const GridPosition(row: 0, col: 1));
    // Cells after the tap are cleared.
    expect(result.grid[0][2], CellState.empty);
    expect(result.grid[1][2], CellState.empty);
  });

  test('retraction counts as a single undo however many cells are removed', () {
    final result = engine.handleCellTap(state, 0, 0);

    expect(result.path.length, 1);
    expect(result.undosUsed, state.undosUsed + 1);
  });

  test('tapping the head does nothing', () {
    final result = engine.handleCellTap(state, 1, 2);

    expect(result.path.length, state.path.length);
    expect(result.undosUsed, state.undosUsed);
  });

  test('retracting past a waypoint restores the waypoint index', () {
    // Walk onto waypoint 2 at (2,2) via a full solution.
    var full = engine.createInitialState();
    for (final cell in const [
      [0, 0],
      [0, 1],
      [0, 2],
      [1, 2],
      [1, 1],
      [1, 0],
      [2, 0],
      [2, 1],
      [2, 2],
    ]) {
      full = engine.addToPath(full, cell[0], cell[1]);
    }
    expect(full.currentWaypointIndex, 1, reason: 'reached waypoint 2');

    final retracted = engine.handleCellTap(full, 1, 1);
    expect(
      retracted.currentWaypointIndex,
      0,
      reason: 'back to waypoint 1 only',
    );
    expect(
      retracted.grid[2][2],
      CellState.waypoint,
      reason: 'waypoint cell is restored, not left filled',
    );
  });

  test('tapping a non-adjacent empty cell is rejected', () {
    final result = engine.handleCellTap(state, 2, 0);
    expect(result.path.length, state.path.length);
  });

  test('tapping an adjacent empty cell still extends', () {
    final result = engine.handleCellTap(state, 1, 1);
    expect(result.path.length, state.path.length + 1);
    expect(result.path.last, const GridPosition(row: 1, col: 1));
  });
}
