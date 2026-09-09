import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../features/puzzle/data/puzzle_session_service.dart';
import '../../features/puzzle/data/score_signature.dart';
import '../../features/puzzle/data/submission_result.dart';
import '../../features/puzzle/providers/daily_puzzle_provider.dart';
import '../../features/puzzle/providers/puzzle_result_provider.dart';
import '../../features/stats/providers/stats_provider.dart';
import 'analytics_service.dart';
import 'app_logger.dart';
import 'auth_session_provider.dart';
import 'connectivity_service.dart';
import 'edge_function_client.dart';
import 'notification_service.dart';
import 'storage_service.dart';
import 'submit_classifier.dart';

part 'sync_service.g.dart';

/// Number of queued items (score submissions + session starts). Emits the
/// current length immediately and again on every change.
@riverpod
Stream<int> syncQueueLength(Ref ref) async* {
  yield StorageService.syncQueueLength;
  yield* StorageService.syncQueue
      .watch()
      .map((_) => StorageService.syncQueueLength);
}

/// Offline-first sync queue for `start-puzzle` and `submit-score` calls.
///
/// State is `true` while a flush is in progress. Items are processed in
/// insertion order; a transient failure stops the flush and schedules an
/// exponential-backoff retry (2^n s, capped at 5 min). Reconnecting flushes
/// immediately.
@Riverpod(keepAlive: true)
class SyncNotifier extends _$SyncNotifier {
  Timer? _retryTimer;
  int _retryCount = 0;
  bool _flushing = false;
  bool _flushRequested = false;

  late EdgeInvoker _invoke;
  late PuzzleSessionService _sessions;

  @override
  bool build() {
    _invoke = ref.watch(edgeInvokerProvider);
    _sessions = PuzzleSessionService(invoker: _invoke);

    ref.listen(connectivityNotifierProvider, (prev, next) {
      if (next && prev == false) {
        _retryCount = 0;
        flush();
      }
    });
    ref.onDispose(() => _retryTimer?.cancel());

    Future<void>.microtask(flush);
    return false;
  }

  /// Requests a `start-puzzle` session for [date]; queues it when offline.
  Future<void> ensureSessionStarted(String date) async {
    final outcome = await _sessions.ensureStarted(date);
    if (outcome == StartSessionOutcome.retry) {
      final alreadyQueued = StorageService.getSyncQueueItems().any(
        (e) => e.value['type'] == 'start_puzzle' && e.value['puzzle_date'] == date,
      );
      if (!alreadyQueued) {
        await StorageService.addToSyncQueue({
          'type': 'start_puzzle',
          'puzzle_date': date,
        });
      }
      _scheduleRetry();
    }
  }

  /// Queues a score submission (works online and offline) and flushes.
  Future<void> queueScoreSubmission({
    required String puzzleDate,
    required int timeSeconds,
    required int hintsUsed,
    required int undosUsed,
    required List<List<int>> path,
    String? signature,
  }) async {
    await StorageService.addToSyncQueue({
      'type': 'submit_score',
      'puzzle_date': puzzleDate,
      'time_seconds': timeSeconds,
      'hints_used': hintsUsed,
      'undos_used': undosUsed,
      'path': path,
      'signature': ?signature,
      'queued_at': DateTime.now().toUtc().toIso8601String(),
    });
    await flush();
  }

  /// Processes the queue now (no-op when empty or already flushing).
  Future<void> flush() async {
    if (_flushing) {
      _flushRequested = true;
      return;
    }
    _flushing = true;
    try {
      bool stoppedForRetry;
      do {
        _flushRequested = false;
        stoppedForRetry = !await _flushOnce();
        // After a transient failure the retry timer owns the next attempt.
      } while (_flushRequested && !stoppedForRetry);
    } finally {
      _flushing = false;
    }
  }

  /// Returns `false` when it stopped on a transient failure.
  Future<bool> _flushOnce() async {
    final items = StorageService.getSyncQueueItems();
    if (items.isEmpty) return true;

    _retryTimer?.cancel();
    state = true;
    try {
      for (final entry in items) {
        final done = await _processQueueItem(entry.value);
        if (!done) {
          _scheduleRetry();
          return false;
        }
        await StorageService.removeSyncQueueItem(entry.key);
        _retryCount = 0;
      }
      return true;
    } finally {
      state = false;
    }
  }

  /// Returns `true` when the item is finished (success or permanent
  /// failure) and can be removed; `false` to retry later.
  Future<bool> _processQueueItem(Map<String, dynamic> item) async {
    switch (item['type'] as String?) {
      case 'submit_score':
        return _submitScore(item);
      case 'start_puzzle':
        final date = item['puzzle_date'] as String?;
        if (date == null) return true;
        final outcome = await _sessions.ensureStarted(date);
        return outcome != StartSessionOutcome.retry;
      default:
        return true;
    }
  }

  Future<bool> _submitScore(Map<String, dynamic> item) async {
    final date = item['puzzle_date'] as String?;
    if (date == null) return true;
    if (!ref.read(authSessionProvider).hasSession) return false;

    final path = [
      for (final cell in (item['path'] as List<dynamic>? ?? const []))
        [
          ((cell as List<dynamic>)[0] as num).toInt(),
          (cell[1] as num).toInt(),
        ],
    ];
    final timeSeconds = (item['time_seconds'] as num).toInt();
    final hintsUsed = (item['hints_used'] as num).toInt();
    final undosUsed = (item['undos_used'] as num).toInt();

    // Sign at flush time so a nonce obtained after queueing still counts.
    var signature = item['signature'] as String?;
    final nonce = StorageService.getSessionNonce(date);
    if (signature == null && nonce != null) {
      signature = computeScoreSignature(
        nonce: nonce,
        puzzleDate: date,
        timeSeconds: timeSeconds,
        hintsUsed: hintsUsed,
        undosUsed: undosUsed,
        path: path,
      );
    }

    final EdgeResponse response;
    try {
      response = await _invoke('submit-score', {
        'puzzle_date': date,
        'time_seconds': timeSeconds,
        'hints_used': hintsUsed,
        'undos_used': undosUsed,
        'path': path,
        'signature': ?signature,
        'queued_at': ?item['queued_at'],
      });
    } catch (e) {
      AppLogger.debug('submit-score unreachable', error: e);
      return false;
    }

    final decision = classifySubmitResponse(response.status, response.body);
    AppLogger.info(
      'submit-score',
      data: {
        'date': date,
        'status': response.status,
        'outcome': decision.outcome.name,
        'code': decision.code,
      },
    );

    switch (decision.outcome) {
      case SubmitOutcome.retry:
        return false;
      case SubmitOutcome.rejected:
        await _recordRejected(date, decision.code, item);
        return true;
      case SubmitOutcome.success:
        await _recordAccepted(date, response, decision, item);
        return true;
    }
  }

  Future<void> _recordRejected(
    String date,
    String? code,
    Map<String, dynamic> item,
  ) async {
    final local = _localResult(date, item);
    await StorageService.saveSubmissionResult(
      date,
      local.copyWith(status: SubmissionStatus.rejected, reason: code).toJson(),
    );
    AppLogger.warn('score rejected', data: {'date': date, 'code': code});
    _notifyResultChanged();
  }

  Future<void> _recordAccepted(
    String date,
    EdgeResponse response,
    SubmitClassification decision,
    Map<String, dynamic> item,
  ) async {
    var result = _localResult(date, item);
    final json = response.json;

    if (decision.alreadyCompleted) {
      // 409: the server has an earlier solve; prefer its values.
      final userId = ref.read(authSessionProvider).userId;
      final server = userId == null
          ? null
          : await ref.read(puzzleRepositoryProvider).getOwnAttempt(userId, date);
      result = server ?? result.copyWith(status: SubmissionStatus.unverified);
    } else if (json != null) {
      result = result.copyWith(
        status: json['verified'] == true
            ? SubmissionStatus.verified
            : SubmissionStatus.unverified,
        isArchive: json['is_archive'] == true,
        streak: json['streak'] is Map<String, dynamic>
            ? StreakSnapshot.fromJson(json['streak'] as Map<String, dynamic>)
            : null,
        rankHint: (json['rank_hint'] as num?)?.toInt(),
      );
    } else {
      result = result.copyWith(status: SubmissionStatus.unverified);
    }

    await StorageService.saveSubmissionResult(date, result.toJson());

    await AnalyticsService.logEvent(AnalyticsEvents.puzzleComplete, {
      'puzzle_date': date,
      'time_seconds': result.timeSeconds,
      'hints_used': result.hintsUsed,
      'undos_used': result.undosUsed,
      'verified': result.status == SubmissionStatus.verified,
      'is_archive': result.isArchive,
    });
    if (!result.isArchive) {
      await NotificationService.cancelStreakReminder();
    }
    _notifyResultChanged();
  }

  SubmissionResult _localResult(String date, Map<String, dynamic> item) {
    final stored = StorageService.getSubmissionResult(date);
    if (stored != null) return SubmissionResult.fromJson(stored);
    return SubmissionResult(
      date: date,
      status: SubmissionStatus.pending,
      timeSeconds: (item['time_seconds'] as num).toInt(),
      hintsUsed: (item['hints_used'] as num).toInt(),
      undosUsed: (item['undos_used'] as num).toInt(),
      path: [
        for (final cell in (item['path'] as List<dynamic>? ?? const []))
          [
            ((cell as List<dynamic>)[0] as num).toInt(),
            (cell[1] as num).toInt(),
          ],
      ],
      completedAt:
          DateTime.tryParse(item['queued_at'] as String? ?? '')?.toUtc() ??
              DateTime.now().toUtc(),
    );
  }

  void _notifyResultChanged() {
    ref.read(submissionResultsVersionProvider.notifier).bump();
    ref.invalidate(statsOverviewProvider);
    ref.invalidate(solveHistoryProvider);
    ref.invalidate(streakProvider);
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    _retryCount++;
    // Exponential backoff: 2^n seconds, max 5 minutes
    final delay = min(pow(2, _retryCount).toInt(), 300);
    _retryTimer = Timer(Duration(seconds: delay), flush);
  }
}
