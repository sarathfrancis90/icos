import 'package:flutter_test/flutter_test.dart';
import 'package:icos/core/services/submit_classifier.dart';

void main() {
  group('classifySubmitResponse', () {
    test('200 completed:true is success', () {
      final c = classifySubmitResponse(200, {
        'completed': true,
        'verified': true,
        'streak': {'current_streak': 3},
      });
      expect(c.outcome, SubmitOutcome.success);
      expect(c.alreadyCompleted, isFalse);
    });

    test('200 completed:false (invalid path) is a permanent rejection', () {
      final c = classifySubmitResponse(200, {
        'completed': false,
        'verified': false,
        'reason': 'Path does not visit every cell',
        'streak': null,
      });
      expect(c.outcome, SubmitOutcome.rejected);
      expect(c.code, 'Path does not visit every cell');
    });

    test('409 ALREADY_COMPLETED is success (idempotent)', () {
      final c = classifySubmitResponse(409, {
        'error': 'already completed',
        'code': 'ALREADY_COMPLETED',
      });
      expect(c.outcome, SubmitOutcome.success);
      expect(c.alreadyCompleted, isTrue);
      expect(c.code, 'ALREADY_COMPLETED');
    });

    test('429 RATE_LIMITED retries later', () {
      final c = classifySubmitResponse(429, {'code': 'RATE_LIMITED'});
      expect(c.outcome, SubmitOutcome.retry);
      expect(c.code, 'RATE_LIMITED');
    });

    test('5xx and 401 retry', () {
      expect(
        classifySubmitResponse(500, {'code': 'INTERNAL'}).outcome,
        SubmitOutcome.retry,
      );
      expect(classifySubmitResponse(503, null).outcome, SubmitOutcome.retry);
      expect(classifySubmitResponse(401, null).outcome, SubmitOutcome.retry);
    });

    for (final code in [
      'INVALID_FIELD',
      'DATE_OUT_OF_RANGE',
      'CLOCK_SKEW',
      'IMPLAUSIBLE_TIME',
      'BAD_SIGNATURE',
      'INVALID_JSON',
    ]) {
      test('400 $code is a permanent rejection', () {
        final c = classifySubmitResponse(400, {'error': 'x', 'code': code});
        expect(c.outcome, SubmitOutcome.rejected);
        expect(c.code, code);
      });
    }

    test('403 BANNED and 404 PUZZLE_NOT_FOUND are permanent', () {
      expect(
        classifySubmitResponse(403, {'code': 'BANNED'}).outcome,
        SubmitOutcome.rejected,
      );
      expect(
        classifySubmitResponse(404, {'code': 'PUZZLE_NOT_FOUND'}).outcome,
        SubmitOutcome.rejected,
      );
    });

    test('non-map bodies are tolerated', () {
      expect(classifySubmitResponse(200, 'ok').outcome, SubmitOutcome.success);
      expect(classifySubmitResponse(400, 'bad').outcome, SubmitOutcome.rejected);
      expect(classifySubmitResponse(429, '').outcome, SubmitOutcome.retry);
    });
  });
}
