import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/services/analytics_service.dart';
import '../../../core/services/app_logger.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/services/sync_service.dart';
import '../data/puzzle_source.dart';
import '../data/submission_result.dart';
import '../domain/game_engine.dart';
import '../domain/models/game_state.dart';
import '../domain/models/puzzle.dart';
import 'hint_engine.dart';

part 'game_provider.g.dart';

/// Transient hint UI state kept outside [GameState] (which lives in the
/// read-only domain layer).
class HintUiState {
  const HintUiState({
    this.thinking = false,
    this.wrongCell,
    this.noHint = false,
  });

  /// Solver is running; hint button shows "Thinking…" and ignores taps.
  final bool thinking;

  /// First cell where the player's path diverged from the solution.
  final GridPosition? wrongCell;

  /// Solver found nothing to suggest (unsolvable / already complete).
  final bool noHint;

  bool get isIdle => !thinking && wrongCell == null && !noHint;

  @override
  bool operator ==(Object other) =>
      other is HintUiState &&
      other.thinking == thinking &&
      other.wrongCell == wrongCell &&
      other.noHint == noHint;

  @override
  int get hashCode => Object.hash(thinking, wrongCell, noHint);
}

@Riverpod(keepAlive: true)
class HintUi extends _$HintUi {
  @override
  HintUiState build(PuzzleSource source) => const HintUiState();

  void thinking() => state = const HintUiState(thinking: true);
  void idle() => state = const HintUiState();
  void wrong(GridPosition cell) => state = HintUiState(wrongCell: cell);
  void none() => state = const HintUiState(noHint: true);
}

/// Game state for one [PuzzleSource]. Kept alive so an in-flight solve or
/// score submission survives the puzzle screen being popped; call
/// [discard] to drop a finished practice game.
@Riverpod(keepAlive: true)
class GameNotifier extends _$GameNotifier {
  GameEngine? _engine;
  Timer? _timer;
  List<GridPosition>? _solution;
  bool _sessionRequested = false;
  bool _disposed = false;

  /// A drag gesture is in flight (between [beginDrag] and [endDrag]).
  bool _dragActive = false;

  /// This drag gesture has already been charged one undo.
  bool _dragUndoCharged = false;

  /// Whether the current state was loaded from a stored result (read-only
  /// replay) rather than played, so it must not be submitted again.
  bool isReplay = false;

  @override
  GameState? build(PuzzleSource source) {
    ref.onDispose(() {
      _disposed = true;
      _timer?.cancel();
    });
    return null;
  }

  /// Starts (or re-attaches to) a game. Idempotent: calling again with the
  /// same puzzle keeps the current state and resumes the timer.
  void startGame(Puzzle puzzle) {
    if (state != null && state!.puzzle == puzzle) {
      resumeTimer();
      return;
    }
    _engine = GameEngine(puzzle);
    _solution = null;
    isReplay = false;
    state = _engine!.createInitialState();
    _restoreGameState();
    if (state!.status == GameStatus.playing) _sessionRequested = true;
  }

  /// Loads a completed solve for read-only viewing.
  void loadCompleted(Puzzle puzzle, SubmissionResult result) {
    _timer?.cancel();
    _engine = GameEngine(puzzle);
    _solution = null;
    isReplay = true;
    var replay = _engine!.createInitialState();
    for (final cell in result.path) {
      if (_engine!.canMoveToCell(replay, cell[0], cell[1])) {
        replay = _engine!.addToPath(replay, cell[0], cell[1]);
      }
    }
    state = replay.copyWith(
      status: GameStatus.completed,
      elapsedSeconds: result.timeSeconds,
      hintsUsed: result.hintsUsed,
      undosUsed: result.undosUsed,
    );
  }

  /// Drops the state (e.g. leaving a practice puzzle) so memory is freed.
  void discard() {
    _timer?.cancel();
    ref.invalidateSelf();
  }

  void handleCellTap(int row, int col) {
    if (state == null || _engine == null) return;
    if (state!.status == GameStatus.completed) return;

    final wasNotStarted = state!.status == GameStatus.notStarted;
    var newState = _engine!.handleCellTap(state!, row, col);
    if (newState == state) return;

    newState = _clearHint(newState);
    _applyMove(newState, wasNotStarted);
  }

  /// Marks the start of a drag gesture. Every retraction until [endDrag] is
  /// treated as part of one undo.
  void beginDrag() {
    _dragActive = true;
    _dragUndoCharged = false;
  }

  /// Marks the end of a drag gesture (also called on cancel).
  void endDrag() {
    _dragActive = false;
  }

  /// Drag across [row], [col]. Dragging backwards over the line retracts to
  /// that cell; dragging onto a legal adjacent cell extends. Shares
  /// [GameEngine.handleCellTap] so tap and drag never diverge.
  ///
  /// A drag may also start the puzzle: pressing on waypoint 1 and sweeping
  /// outwards is the most natural first gesture, so `notStarted` is handled
  /// here exactly as it is for a tap.
  void handleCellDrag(int row, int col) {
    if (state == null || _engine == null) return;
    if (state!.status == GameStatus.completed) return;

    final wasNotStarted = state!.status == GameStatus.notStarted;
    final previousLength = state!.path.length;

    // Sweeping back over four cells should cost what tapping the fourth cell
    // costs: one undo for the gesture, not one per cell crossed.
    final newState = _engine!.handleCellTap(
      state!,
      row,
      col,
      countUndo: !(_dragActive && _dragUndoCharged),
    );
    if (identical(newState, state) || newState == state) return;
    if (newState.path.length < previousLength) _dragUndoCharged = true;

    _applyMove(_clearHint(newState), wasNotStarted);
  }

  /// Whether [row], [col] is a legal extension of the current path. Used by the
  /// grid so input gating and scoring share one rulebook.
  bool canMoveToCell(int row, int col) {
    if (state == null || _engine == null) return false;
    return _engine!.canMoveToCell(state!, row, col);
  }

  void _applyMove(GameState newState, bool wasNotStarted) {
    if (wasNotStarted && newState.status == GameStatus.playing) {
      _startTimer();
      _onFirstMove();
    }
    state = newState;
    if (_engine!.isSolved(newState)) {
      _timer?.cancel();
      state = newState.copyWith(status: GameStatus.completed);
    }
    _saveGameState();
  }

  GameState _clearHint(GameState s) {
    final ui = ref.read(hintUiProvider(source));
    if (!ui.isIdle && !ui.thinking) {
      ref.read(hintUiProvider(source).notifier).idle();
    }
    return s.hintCell != null ? s.copyWith(hintCell: null) : s;
  }

  void undo() {
    if (state == null || _engine == null) return;
    if (state!.status == GameStatus.completed) return;
    state = _clearHint(_engine!.undo(state!));
    _saveGameState();
  }

  void reset() {
    if (state == null || _engine == null) return;
    if (state!.status == GameStatus.completed) return;
    state = _clearHint(_engine!.reset(state!));
    _saveGameState();
  }

  /// Runs the solver off the UI thread and applies the verdict. Re-entrant
  /// taps while thinking are ignored.
  Future<void> useHint() async {
    if (state == null || _engine == null) return;
    if (state!.status == GameStatus.completed) return;
    final hintUi = ref.read(hintUiProvider(source).notifier);
    if (ref.read(hintUiProvider(source)).thinking) return;

    var current = state!;
    if (current.status == GameStatus.notStarted) {
      current = current.copyWith(status: GameStatus.playing);
      state = current;
      _startTimer();
      _onFirstMove();
    }

    hintUi.thinking();
    final puzzle = current.puzzle;
    final path = List<GridPosition>.unmodifiable(current.path);
    final engine = ref.read(hintEngineProvider);

    HintResult result;
    try {
      _solution ??= await engine.solve(puzzle);
      result = await engine.hint(puzzle, path, _solution);
    } catch (e, st) {
      AppLogger.warn('hint solver failed', error: e, st: st);
      result = const HintResult.none();
    }
    if (_disposed || state == null) return;

    // The player kept moving while we were thinking: verdict is stale.
    if (!_samePath(state!.path, path) ||
        state!.status == GameStatus.completed) {
      hintUi.idle();
      return;
    }

    switch (result.type) {
      case HintType.nextCell:
        state = state!.copyWith(
          hintCell: result.cell,
          hintsUsed: state!.hintsUsed + 1,
        );
        hintUi.idle();
      case HintType.wrongCell:
        state = state!.copyWith(
          hintCell: null,
          hintsUsed: state!.hintsUsed + 1,
        );
        hintUi.wrong(result.cell!);
      case HintType.none:
        hintUi.none();
    }
    _saveGameState();
    unawaited(
      AnalyticsService.logEvent(AnalyticsEvents.hintUsed, {
        'type': result.type.name,
        'hints_used': state!.hintsUsed,
      }),
    );
  }

  static bool _samePath(List<GridPosition> a, List<GridPosition> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Stops counting while the puzzle screen is not visible.
  void pauseTimer() {
    _timer?.cancel();
    _timer = null;
    _saveGameState();
  }

  void resumeTimer() {
    if (_timer != null) return;
    if (state?.status == GameStatus.playing) _startTimer();
  }

  void _onFirstMove() {
    if (_sessionRequested) return;
    _sessionRequested = true;
    final date = source.date;
    if (!source.submitsToServer || date == null) return;
    unawaited(
      AnalyticsService.logEvent(AnalyticsEvents.puzzleStart, {
        'puzzle_date': date,
        'archive': source.isArchive,
      }),
    );
    unawaited(
      ref.read(syncNotifierProvider.notifier).ensureSessionStarted(date),
    );
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_disposed) return;
      if (state != null && state!.status == GameStatus.playing) {
        state = state!.copyWith(elapsedSeconds: state!.elapsedSeconds + 1);
        _saveGameState();
      }
    });
  }

  void _saveGameState() {
    if (state == null || isReplay) return;
    final data = {
      'path': state!.path.map((p) => [p.row, p.col]).toList(),
      'elapsed_seconds': state!.elapsedSeconds,
      'hints_used': state!.hintsUsed,
      'undos_used': state!.undosUsed,
      'status': state!.status.name,
    };
    StorageService.saveGameState(source.storageKey, data);
  }

  void _restoreGameState() {
    final saved = StorageService.getGameState(source.storageKey);
    if (saved == null || state == null || _engine == null) return;

    final pathData = (saved['path'] as List<dynamic>?) ?? [];
    var restoredState = _engine!.createInitialState();

    for (final pos in pathData) {
      final coords = pos as List<dynamic>;
      final row = (coords[0] as num).toInt();
      final col = (coords[1] as num).toInt();
      if (_engine!.canMoveToCell(restoredState, row, col)) {
        restoredState = _engine!.addToPath(restoredState, row, col);
      }
    }

    final statusStr = saved['status'] as String? ?? 'notStarted';
    var status = GameStatus.values.firstWhere(
      (s) => s.name == statusStr,
      orElse: () => GameStatus.notStarted,
    );
    // A saved "completed" game whose result was already recorded is replayed
    // read-only; otherwise treat it as still playing so it gets submitted.
    if (status == GameStatus.completed && !_engine!.isSolved(restoredState)) {
      status = GameStatus.playing;
    }

    restoredState = restoredState.copyWith(
      elapsedSeconds: (saved['elapsed_seconds'] as num?)?.toInt() ?? 0,
      hintsUsed: (saved['hints_used'] as num?)?.toInt() ?? 0,
      undosUsed: (saved['undos_used'] as num?)?.toInt() ?? 0,
      status: status,
    );

    state = restoredState;

    if (status == GameStatus.playing) {
      _startTimer();
    }
  }
}
