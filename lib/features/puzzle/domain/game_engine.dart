import 'models/game_state.dart';
import 'models/puzzle.dart';

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

  /// Get a hint: find the next cell to move to that leads to a valid solution.
  /// Uses recursive backtracking to verify the move leads to a solvable state.
  GridPosition? getHint(GameState state) {
    if (state.path.isEmpty) {
      // Must start at the first waypoint
      final firstWp = _puzzle.waypoints.first;
      return GridPosition(row: firstWp.row, col: firstWp.col);
    }

    final last = state.path.last;
    final directions = [
      [0, 1],
      [1, 0],
      [0, -1],
      [-1, 0],
    ];

    // Try each adjacent cell and verify it leads to a valid solution via backtracking
    for (final dir in directions) {
      final nr = last.row + dir[0];
      final nc = last.col + dir[1];
      if (!canMoveToCell(state, nr, nc)) continue;

      // Build a trial state with this move
      final trialState = addToPath(state, nr, nc);

      // Check if this move leads to a solvable state
      if (_canSolveFromState(trialState)) {
        return GridPosition(row: nr, col: nc);
      }
    }

    return null;
  }

  /// Use a hint: find the next cell and return updated state with hint highlighted.
  GameState useHint(GameState state) {
    final hint = getHint(state);
    if (hint == null) return state;
    return state.copyWith(
      hintCell: hint,
      hintsUsed: state.hintsUsed + 1,
    );
  }

  /// Recursive backtracking solver to check if the current state can lead to a solution.
  bool _canSolveFromState(GameState state) {
    // Check if already solved
    if (isSolved(state)) return true;

    // Calculate how many cells we need to fill
    final totalCells = _puzzle.gridSize * _puzzle.gridSize;
    final wallCount = _puzzle.walls.length;
    final requiredCells = totalCells - wallCount;

    // If we've filled all cells but it's not solved, this path is invalid
    if (state.path.length >= requiredCells) return false;

    final last = state.path.last;
    final directions = [
      [0, 1],
      [1, 0],
      [0, -1],
      [-1, 0],
    ];

    for (final dir in directions) {
      final nr = last.row + dir[0];
      final nc = last.col + dir[1];
      if (!canMoveToCell(state, nr, nc)) continue;

      final nextState = addToPath(state, nr, nc);
      if (_canSolveFromState(nextState)) {
        return true;
      }
    }

    return false;
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
