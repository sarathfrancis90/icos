import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icos/core/services/auth_session_provider.dart';
import 'package:icos/core/services/edge_function_client.dart';
import 'package:icos/core/services/storage_service.dart';
import 'package:icos/features/puzzle/data/puzzle_repository.dart';
import 'package:icos/features/puzzle/data/submission_result.dart';
import 'package:icos/features/puzzle/providers/daily_puzzle_provider.dart';
import 'package:icos/features/puzzle/providers/puzzle_result_provider.dart';

import '../../../helpers/storage_test_helpers.dart';

const _date = '2026-09-09';

class _MutableAuth extends AuthSessionInfo {
  _MutableAuth(this.userId);

  @override
  String? userId;

  @override
  bool get hasSession => userId != null;
}

class _SlowRepository extends PuzzleRepository {
  _SlowRepository()
      : super(invoker: (fn, body) async => const EdgeResponse(500, {}));

  final gate = Completer<SubmissionResult?>();

  @override
  Future<SubmissionResult?> getOwnAttempt(String userId, String date) =>
      gate.future;
}

void main() {
  late Directory dir;

  setUp(() async {
    dir = await initTestStorage(userId: 'user-a');
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  test('an attempt fetch that resolves after a user switch does not mark the '
      'new user\'s day solved', () async {
    final auth = _MutableAuth('user-a');
    final repo = _SlowRepository();
    final container = ProviderContainer(
      overrides: [
        authSessionProvider.overrideWithValue(auth),
        puzzleRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);
    final sub = container.listen(puzzleResultProvider(_date), (_, _) {});
    addTearDown(sub.close);

    final pending = container.read(puzzleResultProvider(_date).future);
    await Future<void>.delayed(Duration.zero);

    // Sign in as someone else while user A's lookup is still out.
    auth.userId = 'user-b';
    await StorageService.setActiveUser('user-b');
    repo.gate.complete(
      SubmissionResult(
        date: _date,
        status: SubmissionStatus.verified,
        timeSeconds: 30,
        hintsUsed: 0,
        undosUsed: 0,
        path: const [],
        completedAt: DateTime.utc(2026, 9, 9),
      ),
    );

    expect(await pending, isNull);
    expect(StorageService.getSubmissionResult(_date), isNull);
    expect(StorageService.getSubmissionResult(_date, userId: 'user-a'), isNull);
  });
}
