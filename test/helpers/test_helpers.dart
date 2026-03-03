import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icos/core/theme/app_theme.dart';
import 'package:icos/features/puzzle/domain/models/game_state.dart';
import 'package:icos/features/puzzle/domain/models/puzzle.dart';

/// Call this at the top of each test file's main() to set up GoogleFonts
/// for testing (fonts won't be fetched at runtime in tests).
void setUpTestEnvironment() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
}

/// Wraps a widget in the necessary providers and theme for testing.
Widget buildTestWidget(
  Widget child, {
  List<Override>? overrides,
  ThemeData? theme,
}) {
  return ProviderScope(
    overrides: overrides ?? [],
    child: MaterialApp(
      theme: theme ?? AppTheme.darkTheme,
      home: child,
    ),
  );
}

/// Wraps a widget in a Scaffold for testing standalone widgets.
Widget buildTestWidgetInScaffold(
  Widget child, {
  List<Override>? overrides,
  ThemeData? theme,
}) {
  return ProviderScope(
    overrides: overrides ?? [],
    child: MaterialApp(
      theme: theme ?? AppTheme.darkTheme,
      home: Scaffold(body: child),
    ),
  );
}

/// Creates a standard test puzzle.
const testPuzzle = Puzzle(
  id: 'test-puzzle-1',
  puzzleDate: '2026-03-03',
  gridSize: 5,
  waypoints: [
    Waypoint(order: 1, row: 0, col: 0),
    Waypoint(order: 2, row: 4, col: 4),
  ],
  walls: [
    Wall(row: 2, col: 2),
  ],
  difficulty: 'easy',
  parTimeSeconds: 120,
);

/// Creates a small 3x3 test puzzle for simpler testing.
const smallTestPuzzle = Puzzle(
  id: 'test-puzzle-small',
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

/// Creates a GameState in "not started" status.
GameState createNotStartedGameState({Puzzle puzzle = smallTestPuzzle}) {
  final grid = List.generate(
    puzzle.gridSize,
    (row) => List.generate(
      puzzle.gridSize,
      (col) => CellState.empty,
    ),
  );

  for (final wall in puzzle.walls) {
    grid[wall.row][wall.col] = CellState.wall;
  }
  for (final wp in puzzle.waypoints) {
    grid[wp.row][wp.col] = CellState.waypoint;
  }

  return GameState(
    puzzle: puzzle,
    grid: grid,
    path: const [],
    currentWaypointIndex: 0,
    elapsedSeconds: 0,
    hintsUsed: 0,
    undosUsed: 0,
    status: GameStatus.notStarted,
  );
}

/// Creates a GameState in "playing" status with a short path.
GameState createPlayingGameState({
  Puzzle puzzle = smallTestPuzzle,
  int hintsUsed = 0,
  int undosUsed = 0,
  int elapsedSeconds = 30,
}) {
  final grid = List.generate(
    puzzle.gridSize,
    (row) => List.generate(
      puzzle.gridSize,
      (col) => CellState.empty,
    ),
  );

  for (final wall in puzzle.walls) {
    grid[wall.row][wall.col] = CellState.wall;
  }
  for (final wp in puzzle.waypoints) {
    grid[wp.row][wp.col] = CellState.waypoint;
  }

  // Fill path cells
  grid[0][1] = CellState.filled;

  return GameState(
    puzzle: puzzle,
    grid: grid,
    path: const [
      GridPosition(row: 0, col: 0),
      GridPosition(row: 0, col: 1),
    ],
    currentWaypointIndex: 0,
    elapsedSeconds: elapsedSeconds,
    hintsUsed: hintsUsed,
    undosUsed: undosUsed,
    status: GameStatus.playing,
  );
}

/// Creates a GameState in "completed" status.
GameState createCompletedGameState({
  Puzzle puzzle = smallTestPuzzle,
  int hintsUsed = 0,
  int elapsedSeconds = 45,
}) {
  final grid = List.generate(
    puzzle.gridSize,
    (row) => List.generate(
      puzzle.gridSize,
      (col) => CellState.filled,
    ),
  );

  for (final wall in puzzle.walls) {
    grid[wall.row][wall.col] = CellState.wall;
  }
  for (final wp in puzzle.waypoints) {
    grid[wp.row][wp.col] = CellState.waypoint;
  }

  return GameState(
    puzzle: puzzle,
    grid: grid,
    path: const [
      GridPosition(row: 0, col: 0),
      GridPosition(row: 0, col: 1),
      GridPosition(row: 0, col: 2),
      GridPosition(row: 1, col: 2),
      GridPosition(row: 1, col: 1),
      GridPosition(row: 1, col: 0),
      GridPosition(row: 2, col: 0),
      GridPosition(row: 2, col: 1),
      GridPosition(row: 2, col: 2),
    ],
    currentWaypointIndex: 1,
    elapsedSeconds: elapsedSeconds,
    hintsUsed: hintsUsed,
    undosUsed: 0,
    status: GameStatus.completed,
  );
}
