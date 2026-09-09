import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../domain/game_engine.dart';
import '../domain/models/game_state.dart';
import '../domain/models/puzzle.dart';

part 'hint_engine.g.dart';

/// Async facade over the pure solver so the UI thread never blocks.
abstract class HintEngine {
  /// The puzzle's solution path, or `null` when unsolvable / over budget.
  Future<List<GridPosition>?> solve(Puzzle puzzle);

  /// Hint verdict for [path]; pass a cached [solution] to skip re-solving.
  Future<HintResult> hint(
    Puzzle puzzle,
    List<GridPosition> path,
    List<GridPosition>? solution,
  );
}

/// Runs the solver inside `Isolate.run`.
class IsolateHintEngine implements HintEngine {
  const IsolateHintEngine();

  @override
  Future<List<GridPosition>?> solve(Puzzle puzzle) =>
      Isolate.run(() => solvePuzzle(puzzle));

  @override
  Future<HintResult> hint(
    Puzzle puzzle,
    List<GridPosition> path,
    List<GridPosition>? solution,
  ) {
    final snapshot = List<GridPosition>.unmodifiable(path);
    return Isolate.run(
      () => computeHint(puzzle, snapshot, solution: solution),
    );
  }
}

/// Runs the solver synchronously on the calling isolate (tests, web).
class SyncHintEngine implements HintEngine {
  const SyncHintEngine();

  @override
  Future<List<GridPosition>?> solve(Puzzle puzzle) async => solvePuzzle(puzzle);

  @override
  Future<HintResult> hint(
    Puzzle puzzle,
    List<GridPosition> path,
    List<GridPosition>? solution,
  ) async =>
      computeHint(puzzle, path, solution: solution);
}

@Riverpod(keepAlive: true)
HintEngine hintEngine(Ref ref) => const IsolateHintEngine();
