import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/services/storage_service.dart';
import '../../../core/services/sync_service.dart';
import '../domain/models/game_state.dart';

part 'score_submission_provider.g.dart';

@riverpod
class ScoreSubmitter extends _$ScoreSubmitter {
  @override
  AsyncValue<bool> build() {
    return const AsyncValue.data(false);
  }

  Future<void> submitScore(GameState gameState) async {
    state = const AsyncValue.loading();

    try {
      final path = gameState.path.map((p) => [p.row, p.col]).toList();

      // Queue for sync (works both online and offline)
      await ref.read(syncNotifierProvider.notifier).queueScoreSubmission(
            puzzleDate: gameState.puzzle.puzzleDate,
            timeSeconds: gameState.elapsedSeconds,
            hintsUsed: gameState.hintsUsed,
            undosUsed: gameState.undosUsed,
            path: path,
          );

      // Update local solve count
      await StorageService.incrementSolveCount();

      // Clear saved game state
      await StorageService.clearGameState(gameState.puzzle.puzzleDate);

      state = const AsyncValue.data(true);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}
