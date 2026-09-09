import '../../../core/services/app_logger.dart';
import '../../../core/services/edge_function_client.dart';
import '../../../core/services/storage_service.dart';

enum StartSessionOutcome {
  /// A nonce is stored locally (either already present or just obtained).
  ready,

  /// Transient failure (offline / 5xx / rate limit): caller should queue.
  retry,

  /// Permanent failure (bad date, puzzle missing, banned): nothing to do.
  failed,
}

/// Wraps the `start-puzzle` edge function and persists the per-date nonce
/// used to sign score submissions.
class PuzzleSessionService {
  PuzzleSessionService({EdgeInvoker? invoker})
      : _invoke = invoker ?? supabaseEdgeInvoke;

  final EdgeInvoker _invoke;

  /// Ensures a session nonce exists for [date]. Idempotent: the server
  /// returns the same nonce on repeat calls.
  Future<StartSessionOutcome> ensureStarted(String date) async {
    if (StorageService.getSessionNonce(date) != null) {
      return StartSessionOutcome.ready;
    }
    try {
      final response = await _invoke('start-puzzle', {'puzzle_date': date});
      if (response.status == 200) {
        final nonce = response.json?['nonce'] as String?;
        if (nonce == null || nonce.isEmpty) {
          AppLogger.warn('start-puzzle returned no nonce', data: {'date': date});
          return StartSessionOutcome.failed;
        }
        await StorageService.saveSessionNonce(date, nonce);
        AppLogger.debug('puzzle session started', data: {'date': date});
        return StartSessionOutcome.ready;
      }
      if (response.status == 429 ||
          response.status == 401 ||
          response.status >= 500) {
        return StartSessionOutcome.retry;
      }
      AppLogger.warn(
        'start-puzzle rejected',
        data: {'date': date, 'status': response.status, 'code': response.code},
      );
      return StartSessionOutcome.failed;
    } catch (e) {
      AppLogger.debug('start-puzzle unreachable', error: e);
      return StartSessionOutcome.retry;
    }
  }
}
