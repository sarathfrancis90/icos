import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/services/app_logger.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/services/sync_service.dart';
import '../../../core/utils/date_utils.dart';
import '../../practice/providers/practice_provider.dart';
import '../data/puzzle_source.dart';
import '../data/score_signature.dart';
import '../data/submission_result.dart';
import '../domain/models/game_state.dart';
import 'puzzle_result_provider.dart';

part 'score_submission_provider.g.dart';

/// Server accepts submissions for today … today-7 (UTC).
const int submitWindowDays = 7;

/// Records a completed game locally and (for daily / archive sources) queues
/// it for the server. Kept alive so the submission finishes even when the
/// puzzle screen is popped mid-flight.
@Riverpod(keepAlive: true)
class ScoreSubmitter extends _$ScoreSubmitter {
  @override
  AsyncValue<bool> build() => const AsyncValue.data(false);

  Future<void> submitScore(GameState gameState, PuzzleSource source) async {
    // Already recorded (screen rebuilt, keepAlive state re-attached, …).
    if (StorageService.getSubmissionResult(source.storageKey) != null) {
      state = const AsyncValue.data(true);
      return;
    }
    state = const AsyncValue.loading();

    try {
      final path = gameState.path.map((p) => [p.row, p.col]).toList();
      final now = DateTime.now().toUtc();
      final date = source.date;

      switch (source) {
        case PracticePuzzleSource():
          await StorageService.saveSubmissionResult(
            source.storageKey,
            SubmissionResult(
              date: source.storageKey,
              status: SubmissionStatus.localOnly,
              timeSeconds: gameState.elapsedSeconds,
              hintsUsed: gameState.hintsUsed,
              undosUsed: gameState.undosUsed,
              path: path,
              completedAt: now,
            ).toJson(),
          );
          await ref.read(practiceStatsNotifierProvider.notifier).recordSolve(
                size: source.size,
                timeSeconds: gameState.elapsedSeconds,
              );
        case DailyPuzzleSource():
        case ArchivePuzzleSource():
          final inWindow = AppDateUtils.daysAgo(date!) <= submitWindowDays;
          final nonce = StorageService.getSessionNonce(date);
          final signature = nonce == null
              ? null
              : computeScoreSignature(
                  nonce: nonce,
                  puzzleDate: date,
                  timeSeconds: gameState.elapsedSeconds,
                  hintsUsed: gameState.hintsUsed,
                  undosUsed: gameState.undosUsed,
                  path: path,
                );
          await StorageService.saveSubmissionResult(
            date,
            SubmissionResult(
              date: date,
              status: inWindow
                  ? SubmissionStatus.pending
                  : SubmissionStatus.localOnly,
              timeSeconds: gameState.elapsedSeconds,
              hintsUsed: gameState.hintsUsed,
              undosUsed: gameState.undosUsed,
              path: path,
              completedAt: now,
              isArchive: source.isArchive,
            ).toJson(),
          );
          if (inWindow) {
            await ref.read(syncNotifierProvider.notifier).queueScoreSubmission(
                  puzzleDate: date,
                  timeSeconds: gameState.elapsedSeconds,
                  hintsUsed: gameState.hintsUsed,
                  undosUsed: gameState.undosUsed,
                  path: path,
                  signature: signature,
                );
          } else {
            AppLogger.info(
              'archive solve outside server window; stored locally',
              data: {'date': date},
            );
          }
      }

      await StorageService.incrementSolveCount();
      await StorageService.clearGameState(source.storageKey);
      ref.read(submissionResultsVersionProvider.notifier).bump();
      state = const AsyncValue.data(true);
    } catch (e, st) {
      AppLogger.error('score submission failed', error: e, st: st);
      state = AsyncValue.error(e, st);
    }
  }
}
