import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icos/core/services/analytics_service.dart';
import 'package:icos/core/services/auth_session_provider.dart';
import 'package:icos/core/services/connectivity_service.dart';
import 'package:icos/core/services/edge_function_client.dart';
import 'package:icos/core/services/storage_service.dart';
import 'package:icos/core/services/sync_service.dart';
import 'package:icos/features/puzzle/data/score_signature.dart';
import 'package:icos/features/puzzle/data/submission_result.dart';

import '../../helpers/storage_test_helpers.dart';

class _Online extends ConnectivityNotifier {
  @override
  bool build() => true;
}

typedef _Handler = Future<EdgeResponse> Function(Map<String, dynamic> body);

class _FakeEdge {
  final calls = <(String, Map<String, dynamic>)>[];
  final handlers = <String, _Handler>{};

  Future<EdgeResponse> call(String fn, Map<String, dynamic> body) async {
    calls.add((fn, body));
    final handler = handlers[fn];
    if (handler == null) return const EdgeResponse(200, {});
    return handler(body);
  }
}

const _date = '2026-09-09';
const _path = [
  [0, 0],
  [0, 1],
];

Map<String, dynamic> _submitItem({String? signature}) => {
      'type': 'submit_score',
      'puzzle_date': _date,
      'time_seconds': 42,
      'hints_used': 0,
      'undos_used': 1,
      'path': _path,
      if (signature != null) 'signature': signature,
      'queued_at': '2026-09-09T10:00:00.000Z',
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late _FakeEdge edge;
  late ProviderContainer container;

  setUp(() async {
    tempDir = await initTestStorage();
    edge = _FakeEdge();
    AnalyticsService.testEvents = [];
    container = ProviderContainer(
      overrides: [
        edgeInvokerProvider.overrideWithValue(edge.call),
        connectivityNotifierProvider.overrideWith(_Online.new),
        authSessionProvider.overrideWithValue(const FakeAuthSessionInfo()),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    AnalyticsService.testEvents = null;
    await tempDir.delete(recursive: true);
  });

  SubmissionResult? storedResult() {
    final json = StorageService.getSubmissionResult(_date);
    return json == null ? null : SubmissionResult.fromJson(json);
  }

  group('SyncNotifier', () {
    test('200 completed → removed from queue, result persisted verified',
        () async {
      edge.handlers['submit-score'] = (_) async => const EdgeResponse(200, {
            'completed': true,
            'verified': true,
            'is_archive': false,
            'streak': {
              'current_streak': 5,
              'longest_streak': 9,
              'freeze_count': 1,
              'last_solve_date': _date,
            },
            'rank_hint': 3,
          });
      await StorageService.addToSyncQueue(_submitItem());

      await container.read(syncNotifierProvider.notifier).flush();

      expect(StorageService.syncQueueLength, 0);
      final result = storedResult()!;
      expect(result.status, SubmissionStatus.verified);
      expect(result.streak?.currentStreak, 5);
      expect(result.rankHint, 3);
      expect(result.timeSeconds, 42);
      expect(result.path, _path);
      expect(
        AnalyticsService.testEvents!.map((e) => e.name),
        contains(AnalyticsEvents.puzzleComplete),
      );
      expect(container.read(syncNotifierProvider), isFalse);
    });

    test('409 ALREADY_COMPLETED is treated as success', () async {
      edge.handlers['submit-score'] = (_) async => const EdgeResponse(409, {
            'error': 'already completed',
            'code': 'ALREADY_COMPLETED',
          });
      await StorageService.addToSyncQueue(_submitItem());

      await container.read(syncNotifierProvider.notifier).flush();

      expect(StorageService.syncQueueLength, 0);
      final result = storedResult()!;
      expect(result.isAccepted, isTrue);
      expect(result.isRejected, isFalse);
    });

    test('429 keeps the item for a later retry', () async {
      edge.handlers['submit-score'] =
          (_) async => const EdgeResponse(429, {'code': 'RATE_LIMITED'});
      await StorageService.addToSyncQueue(_submitItem());

      await container.read(syncNotifierProvider.notifier).flush();

      expect(StorageService.syncQueueLength, 1);
      expect(storedResult(), isNull);
      expect(container.read(syncNotifierProvider), isFalse);
    });

    test('transport errors keep the item', () async {
      edge.handlers['submit-score'] = (_) async => throw const SocketException('offline');
      await StorageService.addToSyncQueue(_submitItem());

      await container.read(syncNotifierProvider.notifier).flush();

      expect(StorageService.syncQueueLength, 1);
    });

    test('4xx validation errors drop the item and flag the date as rejected',
        () async {
      edge.handlers['submit-score'] = (_) async => const EdgeResponse(400, {
            'error': 'time_seconds out of range',
            'code': 'IMPLAUSIBLE_TIME',
          });
      await StorageService.addToSyncQueue(_submitItem());

      await container.read(syncNotifierProvider.notifier).flush();

      expect(StorageService.syncQueueLength, 0);
      final result = storedResult()!;
      expect(result.status, SubmissionStatus.rejected);
      expect(result.reason, 'IMPLAUSIBLE_TIME');
      expect(
        AnalyticsService.testEvents!.map((e) => e.name),
        isNot(contains(AnalyticsEvents.puzzleComplete)),
      );
    });

    test('200 completed:false (invalid path) is rejected with the reason',
        () async {
      edge.handlers['submit-score'] = (_) async => const EdgeResponse(200, {
            'completed': false,
            'verified': false,
            'reason': 'Path is not a valid Hamiltonian path',
            'streak': null,
          });
      await StorageService.addToSyncQueue(_submitItem());

      await container.read(syncNotifierProvider.notifier).flush();

      expect(StorageService.syncQueueLength, 0);
      expect(storedResult()!.status, SubmissionStatus.rejected);
      expect(storedResult()!.reason, 'Path is not a valid Hamiltonian path');
    });

    test('items are processed in order and a retry stops the flush', () async {
      var submits = 0;
      edge.handlers['submit-score'] = (body) async {
        submits++;
        return body['puzzle_date'] == '2026-09-08'
            ? const EdgeResponse(429, {'code': 'RATE_LIMITED'})
            : const EdgeResponse(200, {'completed': true, 'verified': false});
      };
      await StorageService.addToSyncQueue(
        _submitItem()..['puzzle_date'] = '2026-09-08',
      );
      await StorageService.addToSyncQueue(_submitItem());

      await container.read(syncNotifierProvider.notifier).flush();

      expect(submits, 1, reason: 'second item must wait for the retry');
      expect(StorageService.syncQueueLength, 2);
    });

    test('queued start-puzzle runs first and its nonce signs the score',
        () async {
      edge.handlers['start-puzzle'] = (body) async => EdgeResponse(200, {
            'puzzle_date': body['puzzle_date'],
            'nonce': 'secret-nonce',
            'started_at': '2026-09-09T09:00:00Z',
            'already_completed': false,
          });
      edge.handlers['submit-score'] = (_) async => const EdgeResponse(200, {
            'completed': true,
            'verified': true,
            'is_archive': false,
            'streak': {
              'current_streak': 1,
              'longest_streak': 1,
              'freeze_count': 1,
            },
          });
      await StorageService.addToSyncQueue({
        'type': 'start_puzzle',
        'puzzle_date': _date,
      });
      await StorageService.addToSyncQueue(_submitItem());

      await container.read(syncNotifierProvider.notifier).flush();

      expect(StorageService.syncQueueLength, 0);
      expect(edge.calls.map((c) => c.$1), ['start-puzzle', 'submit-score']);
      final submitBody = edge.calls.last.$2;
      expect(
        submitBody['signature'],
        computeScoreSignature(
          nonce: 'secret-nonce',
          puzzleDate: _date,
          timeSeconds: 42,
          hintsUsed: 0,
          undosUsed: 1,
          path: _path,
        ),
      );
      expect(submitBody['queued_at'], '2026-09-09T10:00:00.000Z');
      expect(storedResult()!.status, SubmissionStatus.verified);
    });

    test('ensureSessionStarted queues a start_puzzle item when offline',
        () async {
      edge.handlers['start-puzzle'] =
          (_) async => throw const SocketException('offline');

      await container
          .read(syncNotifierProvider.notifier)
          .ensureSessionStarted(_date);

      final items = StorageService.getSyncQueueItems();
      expect(items, hasLength(1));
      expect(items.single.value['type'], 'start_puzzle');
      expect(StorageService.getSessionNonce(_date), isNull);

      // A second request while still offline does not duplicate the item.
      await container
          .read(syncNotifierProvider.notifier)
          .ensureSessionStarted(_date);
      expect(StorageService.syncQueueLength, 1);
    });

    test('without an auth session nothing is sent', () async {
      final noSession = ProviderContainer(
        overrides: [
          edgeInvokerProvider.overrideWithValue(edge.call),
          connectivityNotifierProvider.overrideWith(_Online.new),
          authSessionProvider.overrideWithValue(
            const FakeAuthSessionInfo(hasSession: false, userId: null),
          ),
        ],
      );
      addTearDown(noSession.dispose);
      await StorageService.addToSyncQueue(_submitItem());
      await noSession.read(syncNotifierProvider.notifier).flush();
      expect(edge.calls, isEmpty);
      expect(StorageService.syncQueueLength, 1);
    });
  });

  group('syncQueueLength', () {
    test('emits the current length and updates on change', () async {
      final seen = <int>[];
      final sub = container.listen<AsyncValue<int>>(
        syncQueueLengthProvider,
        (_, next) => next.whenData(seen.add),
        fireImmediately: true,
      );
      addTearDown(sub.close);
      await Future<void>.delayed(Duration.zero);
      await StorageService.addToSyncQueue({'type': 'noop'});
      await Future<void>.delayed(Duration.zero);
      expect(seen.first, 0);
      expect(seen.last, 1);
    });
  });
}
