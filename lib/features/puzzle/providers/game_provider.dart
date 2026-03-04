import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/services/storage_service.dart';
import '../domain/game_engine.dart';
import '../domain/models/game_state.dart';
import '../domain/models/puzzle.dart';

part 'game_provider.g.dart';

@riverpod
class GameNotifier extends _$GameNotifier {
  GameEngine? _engine;
  Timer? _timer;

  @override
  GameState? build() {
    ref.onDispose(() {
      _timer?.cancel();
    });
    return null;
  }

  void startGame(Puzzle puzzle) {
    _engine = GameEngine(puzzle);
    state = _engine!.createInitialState();
    _restoreGameState(puzzle.puzzleDate);
  }

  void handleCellTap(int row, int col) {
    if (state == null || _engine == null) return;
    if (state!.status == GameStatus.completed) return;

    var newState = _engine!.handleCellTap(state!, row, col);

    // Clear hint highlight on any move
    if (newState.hintCell != null) {
      newState = newState.copyWith(hintCell: null);
    }

    // Start timer on first move
    if (state!.status == GameStatus.notStarted &&
        newState.status == GameStatus.playing) {
      _startTimer();
    }

    state = newState;

    // Check for completion
    if (_engine!.isSolved(newState)) {
      _timer?.cancel();
      state = newState.copyWith(status: GameStatus.completed);
    }

    // Auto-save game state
    _saveGameState();
  }

  void handleCellDrag(int row, int col) {
    if (state == null || _engine == null) return;
    if (state!.status == GameStatus.completed) return;
    if (state!.status == GameStatus.notStarted) return;

    // Skip if dragging over the current last cell
    if (state!.path.isNotEmpty &&
        state!.path.last.row == row &&
        state!.path.last.col == col) {
      return;
    }

    // Only allow backtracking to the second-to-last cell (single undo step).
    // Dragging to any other already-visited cell is rejected.
    if (state!.path.length >= 2) {
      final secondToLast = state!.path[state!.path.length - 2];
      if (secondToLast.row == row && secondToLast.col == col) {
        var newState = _engine!.undo(state!);
        if (newState.hintCell != null) {
          newState = newState.copyWith(hintCell: null);
        }
        state = newState;
        _saveGameState();
        return;
      }
    }

    // Reject any move to an already-visited cell
    if (state!.path.any((p) => p.row == row && p.col == col)) {
      return;
    }

    // Otherwise, try adding to path (forward movement)
    if (_engine!.canMoveToCell(state!, row, col)) {
      var newState = _engine!.addToPath(state!, row, col);

      // Clear hint highlight on any move
      if (newState.hintCell != null) {
        newState = newState.copyWith(hintCell: null);
      }

      state = newState;

      if (_engine!.isSolved(newState)) {
        _timer?.cancel();
        state = newState.copyWith(status: GameStatus.completed);
      }

      _saveGameState();
    }
  }

  void undo() {
    if (state == null || _engine == null) return;
    if (state!.status == GameStatus.completed) return;
    state = _engine!.undo(state!);
    _saveGameState();
  }

  void reset() {
    if (state == null || _engine == null) return;
    state = _engine!.reset(state!);
    _saveGameState();
  }

  void useHint() {
    if (state == null || _engine == null) return;
    if (state!.status == GameStatus.completed) return;

    // If the game hasn't started yet, start it and then get the hint
    var currentState = state!;
    if (currentState.status == GameStatus.notStarted) {
      currentState = currentState.copyWith(status: GameStatus.playing);
      _startTimer();
    }

    state = _engine!.useHint(currentState);
    _saveGameState();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (state != null && state!.status == GameStatus.playing) {
        state = state!.copyWith(elapsedSeconds: state!.elapsedSeconds + 1);
      }
    });
  }

  void _saveGameState() {
    if (state == null) return;
    final data = {
      'path': state!.path.map((p) => [p.row, p.col]).toList(),
      'elapsed_seconds': state!.elapsedSeconds,
      'hints_used': state!.hintsUsed,
      'undos_used': state!.undosUsed,
      'status': state!.status.name,
    };
    StorageService.saveGameState(state!.puzzle.puzzleDate, data);
  }

  void _restoreGameState(String puzzleDate) {
    final saved = StorageService.getGameState(puzzleDate);
    if (saved == null || state == null || _engine == null) return;

    final pathData = (saved['path'] as List<dynamic>?) ?? [];
    var restoredState = _engine!.createInitialState();

    for (final pos in pathData) {
      final coords = pos as List<dynamic>;
      final row = coords[0] as int;
      final col = coords[1] as int;
      if (_engine!.canMoveToCell(restoredState, row, col)) {
        restoredState = _engine!.addToPath(restoredState, row, col);
      }
    }

    final statusStr = saved['status'] as String? ?? 'notStarted';
    final status = GameStatus.values.firstWhere(
      (s) => s.name == statusStr,
      orElse: () => GameStatus.notStarted,
    );

    restoredState = restoredState.copyWith(
      elapsedSeconds: (saved['elapsed_seconds'] as int?) ?? 0,
      hintsUsed: (saved['hints_used'] as int?) ?? 0,
      undosUsed: (saved['undos_used'] as int?) ?? 0,
      status: status,
    );

    state = restoredState;

    if (status == GameStatus.playing) {
      _startTimer();
    }
  }
}
