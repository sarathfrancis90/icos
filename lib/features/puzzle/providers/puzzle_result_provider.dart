import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/services/auth_session_provider.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/utils/date_utils.dart';
import '../data/submission_result.dart';
import 'daily_puzzle_provider.dart';

part 'puzzle_result_provider.g.dart';

/// Bumped whenever a local submission result is written so
/// [puzzleResult] providers refresh.
@Riverpod(keepAlive: true)
class SubmissionResultsVersion extends _$SubmissionResultsVersion {
  @override
  int build() => 0;

  void bump() => state = state + 1;
}

/// Completed result for [date]: local record first (instant, offline), then
/// the server's own attempt when nothing conclusive is stored locally.
/// `null` means unsolved.
@riverpod
Future<SubmissionResult?> puzzleResult(Ref ref, String date) async {
  ref.watch(submissionResultsVersionProvider);

  final stored = StorageService.getSubmissionResult(date);
  final local = stored == null ? null : SubmissionResult.fromJson(stored);
  if (local != null && !local.isPending) return local;

  final userId = ref.read(authSessionProvider).userId;
  if (userId == null) return local;

  final server = await ref.read(puzzleRepositoryProvider).getOwnAttempt(
        userId,
        date,
      );
  if (server != null) {
    // Keep the richer local path when the server row has none.
    final merged = server.path.isEmpty && local != null
        ? SubmissionResult(
            date: date,
            status: server.status,
            timeSeconds: server.timeSeconds,
            hintsUsed: server.hintsUsed,
            undosUsed: server.undosUsed,
            path: local.path,
            completedAt: server.completedAt,
            isArchive: server.isArchive,
            streak: local.streak,
            rankHint: local.rankHint,
          )
        : server;
    await StorageService.saveSubmissionResult(date, merged.toJson());
    return merged;
  }
  return local;
}

/// Today's (UTC) result, or `null` when today's puzzle is unsolved.
@riverpod
Future<SubmissionResult?> todayResult(Ref ref) =>
    ref.watch(puzzleResultProvider(AppDateUtils.todayUtc()).future);
