import 'dart:async';
import 'dart:math';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'connectivity_service.dart';
import 'storage_service.dart';
import 'supabase_service.dart';

part 'sync_service.g.dart';

@riverpod
class SyncNotifier extends _$SyncNotifier {
  Timer? _retryTimer;
  int _retryCount = 0;

  @override
  bool build() {
    ref.listen(connectivityNotifierProvider, (prev, next) {
      if (next == true && prev == false) {
        // Reconnected — flush sync queue
        _flushSyncQueue();
      }
    });
    ref.onDispose(() => _retryTimer?.cancel());

    // Try initial flush
    _flushSyncQueue();
    return false; // not syncing
  }

  /// Add a score submission to the sync queue for offline processing.
  Future<void> queueScoreSubmission({
    required String puzzleDate,
    required int timeSeconds,
    required int hintsUsed,
    required int undosUsed,
    required List<List<int>> path,
  }) async {
    await StorageService.addToSyncQueue({
      'type': 'submit_score',
      'puzzle_date': puzzleDate,
      'time_seconds': timeSeconds,
      'hints_used': hintsUsed,
      'undos_used': undosUsed,
      'path': path,
      'queued_at': DateTime.now().toUtc().toIso8601String(),
    });

    // Try to flush immediately
    await _flushSyncQueue();
  }

  Future<void> _flushSyncQueue() async {
    final items = StorageService.getSyncQueueItems();
    if (items.isEmpty) return;

    state = true; // syncing

    for (final entry in items) {
      final success = await _processQueueItem(entry.value);
      if (success) {
        await StorageService.removeSyncQueueItem(entry.key);
        _retryCount = 0;
      } else {
        // Exponential backoff retry
        _scheduleRetry();
        break;
      }
    }

    state = false; // done syncing
  }

  Future<bool> _processQueueItem(Map<String, dynamic> item) async {
    final type = item['type'] as String?;

    switch (type) {
      case 'submit_score':
        return _submitScore(item);
      default:
        // Unknown type — remove it
        return true;
    }
  }

  Future<bool> _submitScore(Map<String, dynamic> item) async {
    try {
      final session = SupabaseService.auth.currentSession;
      if (session == null) return false;

      final response = await SupabaseService.functions.invoke(
        'submit-score',
        body: {
          'puzzle_date': item['puzzle_date'],
          'time_seconds': item['time_seconds'],
          'hints_used': item['hints_used'],
          'undos_used': item['undos_used'],
          'path': item['path'],
        },
      );

      // 409 = already submitted (treat as success)
      return response.status == 200 || response.status == 409;
    } catch (_) {
      return false;
    }
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    _retryCount++;
    // Exponential backoff: 2^n seconds, max 5 minutes
    final delay = min(pow(2, _retryCount).toInt(), 300);
    _retryTimer = Timer(Duration(seconds: delay), _flushSyncQueue);
  }
}
