/// Bridges between the app's `Puzzle`/`GridPosition` models and the
/// index-based puzzle core.
library;

import '../models/game_state.dart' show GridPosition;
import '../models/puzzle.dart';
import 'generator.dart';
import 'grid.dart';
import 'solver.dart';

/// Wall cell indices of a puzzle.
Set<int> wallIndices(Puzzle puzzle) => {
      for (final w in puzzle.walls) w.row * puzzle.gridSize + w.col,
    };

/// Waypoint cell indices sorted by `order`.
List<int> waypointIndices(Puzzle puzzle) {
  final sorted = puzzle.waypoints.toList()
    ..sort((a, b) => a.order.compareTo(b.order));
  return [for (final w in sorted) w.row * puzzle.gridSize + w.col];
}

List<int> pathIndices(int size, List<GridPosition> path) =>
    [for (final p in path) p.row * size + p.col];

List<List<int>> pathCells(List<GridPosition> path) =>
    [for (final p in path) [p.row, p.col]];

List<GridPosition> positionsFromIndices(int size, List<int> indices) => [
      for (final i in indices) GridPosition(row: i ~/ size, col: i % size),
    ];

/// Whether the puzzle's open cells admit a Hamiltonian path at all.
bool isPuzzleFeasible(Puzzle puzzle) =>
    isHamiltonianFeasible(puzzle.gridSize, wallIndices(puzzle));

/// Validates a drawn path against the puzzle using the shared contract.
PathValidation validatePuzzlePath(Puzzle puzzle, List<GridPosition> path) =>
    validatePath(
      puzzle.gridSize,
      wallIndices(puzzle),
      waypointIndices(puzzle),
      pathCells(path),
    );

/// Runs the solver on a puzzle model.
SolveResult solvePuzzleModel(
  Puzzle puzzle, {
  int limit = 2,
  int nodeBudget = 300000,
  List<GridPosition>? prefix,
}) =>
    countSolutions(
      puzzle.gridSize,
      wallIndices(puzzle),
      waypointIndices(puzzle),
      limit: limit,
      nodeBudget: nodeBudget,
      prefix: prefix == null ? null : pathIndices(puzzle.gridSize, prefix),
    );

/// Converts generator output into the app's `Puzzle` model.
Puzzle puzzleFromGenerated(
  GeneratedPuzzle generated, {
  required String id,
  required String puzzleDate,
}) {
  final size = generated.gridSize;
  return Puzzle(
    id: id,
    puzzleDate: puzzleDate,
    gridSize: size,
    waypoints: [
      for (var i = 0; i < generated.waypoints.length; i++)
        Waypoint(
          order: i + 1,
          row: generated.waypoints[i] ~/ size,
          col: generated.waypoints[i] % size,
        ),
    ],
    walls: [
      for (final w in generated.walls) Wall(row: w ~/ size, col: w % size),
    ],
    difficulty: generated.difficulty.name,
    parTimeSeconds: generated.parTimeSeconds,
    difficultyScore: generated.difficultyScore,
  );
}
