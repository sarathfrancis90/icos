import 'dart:collection';

import 'models/game_state.dart';
import 'models/puzzle.dart';
import 'solver/puzzle_core.dart';

class GameEngine {
  GameEngine(this._puzzle);

  final Puzzle _puzzle;

  GameState createInitialState() {
    final grid = List.generate(
      _puzzle.gridSize,
      (row) => List.generate(
        _puzzle.gridSize,
        (col) => CellState.empty,
      ),
    );

    // Place walls
    for (final wall in _puzzle.walls) {
      grid[wall.row][wall.col] = CellState.wall;
    }

    // Place waypoints
    for (final wp in _puzzle.waypoints) {
      grid[wp.row][wp.col] = CellState.waypoint;
    }

    return GameState(
      puzzle: _puzzle,
      grid: grid,
      path: [],
      currentWaypointIndex: 0,
      elapsedSeconds: 0,
      hintsUsed: 0,
      undosUsed: 0,
      status: GameStatus.notStarted,
    );
  }

  /// Check if a cell can be added to the path.
  bool canMoveToCell(GameState state, int row, int col) {
    if (row < 0 ||
        row >= _puzzle.gridSize ||
        col < 0 ||
        col >= _puzzle.gridSize) {
      return false;
    }

    // Can't move to wall
    if (state.grid[row][col] == CellState.wall) return false;

    // If path is empty, must start at first waypoint
    if (state.path.isEmpty) {
      final firstWp = _puzzle.waypoints.first;
      return row == firstWp.row && col == firstWp.col;
    }

    // Must be adjacent to last cell in path
    final last = state.path.last;
    final isAdjacent = (row - last.row).abs() + (col - last.col).abs() == 1;
    if (!isAdjacent) return false;

    // Can't revisit a cell already in path
    if (state.path.any((p) => p.row == row && p.col == col)) return false;

    // If it's a waypoint, it must be the next one in sequence
    final waypointAtCell = _findWaypointAt(row, col);
    if (waypointAtCell != null) {
      if (waypointAtCell.order != state.currentWaypointIndex + 2) {
        // +2 because currentWaypointIndex is 0-based and waypoint orders start at 1
        // If we've visited waypoint 1 (index 0), next must be waypoint 2
        return false;
      }
    }

    return true;
  }

  /// Add a cell to the path.
  GameState addToPath(GameState state, int row, int col) {
    if (!canMoveToCell(state, row, col)) return state;

    final newPath = [...state.path, GridPosition(row: row, col: col)];
    final newGrid = _copyGrid(state.grid);
    newGrid[row][col] =
        state.grid[row][col] == CellState.waypoint
            ? CellState.waypoint
            : CellState.filled;

    var nextWaypointIndex = state.currentWaypointIndex;
    final waypointAtCell = _findWaypointAt(row, col);
    if (waypointAtCell != null) {
      nextWaypointIndex = waypointAtCell.order - 1;
    }

    final newStatus =
        state.status == GameStatus.notStarted
            ? GameStatus.playing
            : state.status;

    return state.copyWith(
      path: newPath,
      grid: newGrid,
      currentWaypointIndex: nextWaypointIndex,
      status: newStatus,
    );
  }

  /// Backtrack the path to the given cell, removing all cells after it.
  /// Returns null if the cell is not in the path or is the last cell.
  GameState? backtrackToCell(GameState state, int row, int col) {
    final index = state.path.indexWhere((p) => p.row == row && p.col == col);
    if (index < 0 || index >= state.path.length - 1) return null;

    final newPath = state.path.sublist(0, index + 1);
    final removedCells = state.path.sublist(index + 1);

    final newGrid = _copyGrid(state.grid);
    for (final cell in removedCells) {
      final waypointAtCell = _findWaypointAt(cell.row, cell.col);
      newGrid[cell.row][cell.col] =
          waypointAtCell != null ? CellState.waypoint : CellState.empty;
    }

    // Recalculate current waypoint index
    var waypointIndex = 0;
    for (final pos in newPath) {
      final wp = _findWaypointAt(pos.row, pos.col);
      if (wp != null) {
        waypointIndex = wp.order - 1;
      }
    }

    return state.copyWith(
      path: newPath,
      grid: newGrid,
      currentWaypointIndex: waypointIndex,
    );
  }

  /// Remove the last cell from the path (undo).
  GameState undo(GameState state) {
    if (state.path.isEmpty) return state;

    final newPath = state.path.sublist(0, state.path.length - 1);
    final removed = state.path.last;

    final newGrid = _copyGrid(state.grid);
    // Restore cell state
    final waypointAtCell = _findWaypointAt(removed.row, removed.col);
    newGrid[removed.row][removed.col] =
        waypointAtCell != null ? CellState.waypoint : CellState.empty;

    // Recalculate current waypoint index
    var waypointIndex = 0;
    for (final pos in newPath) {
      final wp = _findWaypointAt(pos.row, pos.col);
      if (wp != null) {
        waypointIndex = wp.order - 1;
      }
    }

    return state.copyWith(
      path: newPath,
      grid: newGrid,
      currentWaypointIndex: waypointIndex,
      undosUsed: state.undosUsed + 1,
    );
  }

  /// Reset the entire path.
  GameState reset(GameState state) {
    return createInitialState().copyWith(
      elapsedSeconds: state.elapsedSeconds,
      hintsUsed: state.hintsUsed,
      undosUsed: state.undosUsed,
      status: GameStatus.playing,
    );
  }

  /// Check if the puzzle is solved.
  bool isSolved(GameState state) {
    // All waypoints must be visited in order
    if (state.currentWaypointIndex != _puzzle.waypoints.length - 1) {
      return false;
    }

    // Last cell in path must be the last waypoint
    if (state.path.isEmpty) return false;
    final lastWp = _puzzle.waypoints.last;
    final lastCell = state.path.last;
    if (lastCell.row != lastWp.row || lastCell.col != lastWp.col) {
      return false;
    }

    // All non-wall cells must be filled
    final totalCells = _puzzle.gridSize * _puzzle.gridSize;
    final wallCount = _puzzle.walls.length;
    final requiredCells = totalCells - wallCount;

    return state.path.length == requiredCells;
  }

  /// Allow backtracking: if user taps the second-to-last cell, remove the last.
  GameState handleCellTap(GameState state, int row, int col) {
    // If tapping the second-to-last cell, undo
    if (state.path.length >= 2) {
      final secondToLast = state.path[state.path.length - 2];
      if (secondToLast.row == row && secondToLast.col == col) {
        return undo(state);
      }
    }

    // Otherwise try to add
    return addToPath(state, row, col);
  }

  /// Next cell to move to, or `null` if the current path cannot be completed
  /// (or the puzzle is already complete). See [getHintResult] for the richer
  /// verdict that distinguishes a wrong move from "no hint".
  GridPosition? getHint(GameState state) {
    final result = getHintResult(state);
    return result.type == HintType.nextCell ? result.cell : null;
  }

  /// Solver-backed hint verdict for the current path.
  HintResult getHintResult(GameState state) => computeHint(_puzzle, state.path);

  /// Use a hint: highlight the next cell and count the hint. Returns the
  /// state unchanged when no forward hint is available (wrong move or done);
  /// callers wanting to surface the wrong cell should use [getHintResult].
  GameState useHint(GameState state) {
    final hint = getHint(state);
    if (hint == null) return state;
    return state.copyWith(
      hintCell: hint,
      hintsUsed: state.hintsUsed + 1,
    );
  }

  Waypoint? _findWaypointAt(int row, int col) {
    for (final wp in _puzzle.waypoints) {
      if (wp.row == row && wp.col == col) return wp;
    }
    return null;
  }

  List<List<CellState>> _copyGrid(List<List<CellState>> grid) {
    return grid.map((row) => [...row]).toList();
  }
}

enum HintType { nextCell, wrongCell, none }

/// Outcome of [computeHint].
class HintResult {
  const HintResult._(this.type, this.cell);

  const HintResult.nextCell(GridPosition cell) : this._(HintType.nextCell, cell);
  const HintResult.wrongCell(GridPosition cell)
      : this._(HintType.wrongCell, cell);
  const HintResult.none() : this._(HintType.none, null);

  final HintType type;

  /// The cell to move to next ([HintType.nextCell]) or the first cell where
  /// the path went wrong ([HintType.wrongCell]). `null` for [HintType.none].
  final GridPosition? cell;

  @override
  bool operator ==(Object other) =>
      other is HintResult && other.type == type && other.cell == cell;

  @override
  int get hashCode => Object.hash(type, cell);

  @override
  String toString() => 'HintResult(${type.name}, $cell)';
}

/// Node budget for the fallback "can this path still be completed?" solve.
const int _kPrefixSolveBudget = 60000;

/// Pure hint computation, safe to run inside `Isolate.run`.
///
/// Solves the puzzle (the solution is cached per puzzle in a small LRU) and:
/// * returns [HintType.nextCell] with the cell following `path` when `path`
///   is a prefix of the solution;
/// * otherwise, if the path can still be completed (only possible for
///   non-unique puzzles), returns the next cell of such a completion;
/// * otherwise returns [HintType.wrongCell] with the first cell at which the
///   path diverges from the solution;
/// * returns [HintType.none] when the puzzle is unsolvable, the path is
///   already complete, or the solver budget was exhausted.
///
/// Pass a precomputed `solution` (from [solvePuzzle]) to skip the solve.
HintResult computeHint(
  Puzzle puzzle,
  List<GridPosition> path, {
  List<GridPosition>? solution,
}) {
  final size = puzzle.gridSize;
  final solved = solution ?? solvePuzzle(puzzle);
  if (solved == null) return const HintResult.none();
  if (path.length >= solved.length) return const HintResult.none();

  var divergence = -1;
  for (var i = 0; i < path.length; i++) {
    if (path[i] != solved[i]) {
      divergence = i;
      break;
    }
  }
  if (divergence < 0) return HintResult.nextCell(solved[path.length]);

  // Not a prefix of the cached solution. For puzzles with several solutions
  // the player may still be on a valid line, so try completing their path.
  final res = solvePuzzleModel(
    puzzle,
    limit: 1,
    nodeBudget: _kPrefixSolveBudget,
    prefix: path,
  );
  if (res.count == 1) {
    final alt = positionsFromIndices(size, res.solutions.first);
    _SolutionCache.put(puzzle, alt);
    return HintResult.nextCell(alt[path.length]);
  }
  return HintResult.wrongCell(path[divergence]);
}

/// Solves the puzzle and returns its solution path, or `null` if it has none
/// (or the solver budget was exhausted). Cached per puzzle in a small LRU.
///
/// Pure; suitable for `Isolate.run(() => solvePuzzle(puzzle))`. Note that the
/// cache is per-isolate, so a solution computed in a short-lived isolate
/// should be passed back into [computeHint] via its `solution` parameter.
List<GridPosition>? solvePuzzle(Puzzle puzzle, {int nodeBudget = 300000}) {
  final cached = _SolutionCache.get(puzzle);
  if (cached != null) return cached;
  final res = solvePuzzleModel(puzzle, limit: 1, nodeBudget: nodeBudget);
  if (res.count < 1) return null;
  final solution = positionsFromIndices(puzzle.gridSize, res.solutions.first);
  _SolutionCache.put(puzzle, solution);
  return solution;
}

/// Small LRU keyed by puzzle id plus a content fingerprint so that puzzles
/// that reuse an id (tests, practice mode) never collide.
class _SolutionCache {
  static const int capacity = 4;
  static final LinkedHashMap<String, List<GridPosition>> _entries =
      LinkedHashMap<String, List<GridPosition>>();

  static String _key(Puzzle p) {
    final walls = p.walls.map((w) => '${w.row},${w.col}').join(';');
    final wps = p.waypoints.map((w) => '${w.order}:${w.row},${w.col}').join(';');
    return '${p.id}|${p.gridSize}|$walls|$wps';
  }

  static List<GridPosition>? get(Puzzle p) {
    final key = _key(p);
    final value = _entries.remove(key);
    if (value == null) return null;
    _entries[key] = value;
    return value;
  }

  static void put(Puzzle p, List<GridPosition> solution) {
    final key = _key(p);
    _entries.remove(key);
    _entries[key] = List<GridPosition>.unmodifiable(solution);
    while (_entries.length > capacity) {
      _entries.remove(_entries.keys.first);
    }
  }
}
