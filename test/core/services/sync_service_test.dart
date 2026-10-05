import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icos/core/services/analytics_service.dart';
import 'package:icos/core/services/auth_session_provider.dart';
import 'package:icos/core/services/connectivity_service.dart';
import 'package:icos/core/services/edge_function_client.dart';
import 'package:icos/core/services/session_service.dart';
import 'package:icos/core/services/storage_service.dart';
import 'package:icos/core/services/sync_service.dart';
import 'package:icos/features/puzzle/data/score_signature.dart';
import 'package:icos/features/puzzle/data/submission_result.dart';

import '../../helpers/storage_test_helpers.dart';

class _Online extends ConnectivityNotifier {
  @override
  bool build() => true;
}

class _MutableAuth extends AuthSessionInfo {
  _MutableAuth(this.userId);

  @override
  String? userId;

  @override
  bool get hasSession => userId != null;
}

class _SignedInGateway implements SessionGateway {
  @override
  bool get hasSession => true;

  @override
  Future<void> signInAnonymously() async {}
}

class _CountingGateway implements SessionGateway {
  int signInCalls = 0;
  bool _has = false;

  @override
  bool get hasSession => _has;

  @override
  Future<void> signInAnonymously() async {
    signInCalls++;
    _has = true;
  }
}

final _ensurer = SessionEnsurer(gateway: _SignedInGateway());

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
        sessionEnsurerProvider.overrideWithValue(_ensurer),
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
          sessionEnsurerProvider.overrideWithValue(_ensurer),
        ],
      );
      addTearDown(noSession.dispose);
      await StorageService.addToSyncQueue(_submitItem());
      await noSession.read(syncNotifierProvider.notifier).flush();
      expect(edge.calls, isEmpty);
      expect(StorageService.syncQueueLength, 1);
    });
  });

  test('makes sure a session exists before the queue runs', () async {
    final gateway = _CountingGateway();
    final c = ProviderContainer(
      overrides: [
        edgeInvokerProvider.overrideWithValue(edge.call),
        connectivityNotifierProvider.overrideWith(_Online.new),
        authSessionProvider.overrideWithValue(const FakeAuthSessionInfo()),
        sessionEnsurerProvider.overrideWithValue(
          SessionEnsurer(gateway: gateway),
        ),
      ],
    );
    addTearDown(c.dispose);
    await StorageService.addToSyncQueue(_submitItem());

    await c.read(syncNotifierProvider.notifier).flush();

    expect(gateway.signInCalls, 1);
  });

  group('user switching during a flush', () {
    test('the second entry is not submitted and stays queued for its owner',
        () async {
      final auth = _MutableAuth('test-user');
      final c = ProviderContainer(
        overrides: [
          edgeInvokerProvider.overrideWithValue(edge.call),
          connectivityNotifierProvider.overrideWith(_Online.new),
          authSessionProvider.overrideWithValue(auth),
          sessionEnsurerProvider.overrideWithValue(_ensurer),
        ],
      );
      addTearDown(c.dispose);
      await StorageService.addToSyncQueue(_submitItem());
      await StorageService.addToSyncQueue({..._submitItem(), 'puzzle_date': '2026-09-08'});
      edge.handlers['submit-score'] = (_) async {
        // The user signs in to another account while the request is out.
        auth.userId = 'other-user';
        await StorageService.setActiveUser('other-user');
        return const EdgeResponse(200, {'completed': true, 'verified': true});
      };

      await c.read(syncNotifierProvider.notifier).flush();

      expect(edge.calls.where((c) => c.$1 == 'submit-score'), hasLength(1));
      final left = StorageService.getSyncQueueItems();
      expect(left, hasLength(1));
      expect(left.single.value['user_id'], 'test-user');
      expect(left.single.value['puzzle_date'], '2026-09-08');
      // The first result was saved for the user who submitted it.
      expect(StorageService.getSubmissionResult(_date), isNull);
      expect(
        StorageService.getSubmissionResult(_date, userId: 'test-user'),
        isNotNull,
      );
    });

    test('a legacy entry with no user id is stamped and submitted in the '
        'same flush', () async {
      await StorageService.syncQueue.put(
        '00001000000000',
        jsonEncode(_submitItem()),
      );
      expect(
        StorageService.getSyncQueueItems().single.value['user_id'],
        isNull,
      );

      await container.read(syncNotifierProvider.notifier).flush();

      expect(edge.calls.where((c) => c.$1 == 'submit-score'), hasLength(1));
      expect(StorageService.getSyncQueueItems(), isEmpty);
    });
  });

  group('per-user queue', () {
    test('an entry created under another user is not submitted for this one',
        () async {
      // Guest solved offline, then signed in to an existing account.
      await StorageService.setActiveUser('guest-user');
      await StorageService.addToSyncQueue(_submitItem());
      await StorageService.setActiveUser('test-user');

      await container.read(syncNotifierProvider.notifier).flush();

      expect(edge.calls, isEmpty);
      final left = StorageService.getSyncQueueItems();
      expect(left, hasLength(1));
      expect(left.single.value['user_id'], 'guest-user');
    });

    test('own entries still go out past another user\'s entry', () async {
      await StorageService.setActiveUser('guest-user');
      await StorageService.addToSyncQueue(_submitItem());
      await StorageService.setActiveUser('test-user');
      await StorageService.addToSyncQueue(_submitItem());
      edge.handlers['submit-score'] = (_) async =>
          const EdgeResponse(200, {'completed': true, 'verified': true});

      await container.read(syncNotifierProvider.notifier).flush();

      expect(edge.calls.where((c) => c.$1 == 'submit-score'), hasLength(1));
      expect(
        StorageService.getSyncQueueItems().map((e) => e.value['user_id']),
        ['guest-user'],
      );
    });

    test('the guest\'s entry syncs when the guest signs back in', () async {
      await StorageService.setActiveUser('guest-user');
      await StorageService.addToSyncQueue(_submitItem());
      final asGuest = ProviderContainer(
        overrides: [
          edgeInvokerProvider.overrideWithValue(edge.call),
          connectivityNotifierProvider.overrideWith(_Online.new),
          authSessionProvider.overrideWithValue(
            const FakeAuthSessionInfo(userId: 'guest-user'),
          ),
          sessionEnsurerProvider.overrideWithValue(_ensurer),
        ],
      );
      addTearDown(asGuest.dispose);

      await asGuest.read(syncNotifierProvider.notifier).flush();

      expect(edge.calls.where((c) => c.$1 == 'submit-score'), hasLength(1));
      expect(StorageService.getSyncQueueItems(), isEmpty);
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
