/// What the sync queue should do with a `submit-score` response.
enum SubmitOutcome {
  /// Accepted (200 completed, or 409 ALREADY_COMPLETED): remove from queue.
  success,

  /// Transient (429, 5xx, 401 while the session refreshes): keep and retry
  /// with backoff.
  retry,

  /// Permanent (validation errors, banned, not found, invalid path): remove
  /// from queue and flag the date as not counted.
  rejected,
}

/// Pure classification of a `submit-score` HTTP response.
class SubmitClassification {
  const SubmitClassification({
    required this.outcome,
    this.code,
    this.alreadyCompleted = false,
  });

  final SubmitOutcome outcome;

  /// Server `code` (errors) or `reason` (`completed:false`), when present.
  final String? code;

  /// True for 409 ALREADY_COMPLETED — success, but the body carries no
  /// streak / rank data.
  final bool alreadyCompleted;

  @override
  String toString() =>
      'SubmitClassification(${outcome.name}, code: $code, already: $alreadyCompleted)';
}

/// Maps a `submit-score` status + JSON body to a queue decision.
///
/// * 200 with `completed:true` → success
/// * 200 with `completed:false` → rejected (invalid path; resubmitting the
///   same path cannot succeed)
/// * 409 → success (`ALREADY_COMPLETED`)
/// * 429 / 5xx / 401 / 408 → retry
/// * any other 4xx → rejected
SubmitClassification classifySubmitResponse(int status, Object? body) {
  final json = body is Map<String, dynamic> ? body : const <String, dynamic>{};
  final code = (json['code'] ?? json['reason']) as String?;

  if (status == 200 || status == 201) {
    final completed = json['completed'];
    if (completed == false) {
      return SubmitClassification(
        outcome: SubmitOutcome.rejected,
        code: code ?? 'INVALID_PATH',
      );
    }
    return const SubmitClassification(outcome: SubmitOutcome.success);
  }
  if (status == 409) {
    return SubmitClassification(
      outcome: SubmitOutcome.success,
      code: code ?? 'ALREADY_COMPLETED',
      alreadyCompleted: true,
    );
  }
  if (status == 429 || status == 401 || status == 408 || status >= 500) {
    return SubmitClassification(outcome: SubmitOutcome.retry, code: code);
  }
  if (status >= 400) {
    return SubmitClassification(outcome: SubmitOutcome.rejected, code: code);
  }
  // Unexpected 2xx/3xx without a body we understand: treat as success so a
  // stale item never blocks the queue forever.
  return const SubmitClassification(outcome: SubmitOutcome.success);
}
