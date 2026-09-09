import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/services/auth_session_provider.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/result.dart';
import '../../puzzle/data/submission_result.dart';
import '../../puzzle/providers/daily_puzzle_provider.dart';
import '../../puzzle/providers/puzzle_result_provider.dart';

part 'archive_provider.g.dart';

/// Number of past days shown in the archive (today excluded).
const archiveDays = 30;

class ArchiveEntry {
  const ArchiveEntry({required this.date, this.result});

  final String date;
  final SubmissionResult? result;

  bool get solved => result != null && !result!.isRejected;
  bool get rejected => result?.isRejected ?? false;
}

/// The last [archiveDays] UTC dates (newest first) with the user's solve
/// status, merged from local records and the server's own attempts.
@riverpod
Future<List<ArchiveEntry>> archiveEntries(Ref ref) async {
  ref.watch(submissionResultsVersionProvider);
  var dates = AppDateUtils.recentDates(archiveDays);

  // Only list days that actually have a puzzle on the server. If the lookup
  // fails (offline), keep the full range so cached puzzles stay reachable.
  final available = await ref
      .read(puzzleRepositoryProvider)
      .getAvailableDates(from: dates.last, to: dates.first);
  if (available case Success(data: final serverDates)) {
    final set = serverDates.toSet();
    final filtered = [
      for (final d in dates)
        if (set.contains(d)) d,
    ];
    if (filtered.isNotEmpty) dates = filtered;
  }

  final merged = <String, SubmissionResult>{};
  for (final date in dates) {
    final stored = StorageService.getSubmissionResult(date);
    if (stored != null) merged[date] = SubmissionResult.fromJson(stored);
  }

  final userId = ref.read(authSessionProvider).userId;
  if (userId != null) {
    final server = await ref
        .read(puzzleRepositoryProvider)
        .getOwnAttempts(userId, from: dates.last, to: dates.first);
    if (server case Success(data: final rows)) {
      for (final row in rows) {
        final local = merged[row.date];
        if (local == null || local.isPending) merged[row.date] = row;
      }
    }
  }

  return [for (final d in dates) ArchiveEntry(date: d, result: merged[d])];
}
