import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icos/core/services/edge_function_client.dart';
import 'package:icos/core/utils/app_error.dart';
import 'package:icos/core/utils/result.dart';
import 'package:icos/features/groups/data/group_repository.dart';
import 'package:icos/features/groups/domain/models/group.dart';
import 'package:icos/features/groups/providers/groups_provider.dart';
import 'package:postgrest/postgrest.dart';

GroupFeedEvent _event(int id) => GroupFeedEvent(
  id: '$id',
  groupId: 'g-1',
  userId: 'u-$id',
  event: 'solved',
  createdAt: DateTime.utc(2026, 11, 8, 10, id),
);

/// Records every feed fetch; [next] is what the following fetch returns.
class _FakeRepo extends GroupRepository {
  _FakeRepo()
    : super(
        client: () => PostgrestClient('http://localhost/rest/v1'),
        invoker: (_, _) async => const EdgeResponse(200, {}),
        userId: () => 'u-1',
      );

  final fetches = <String?>[];
  Result<List<GroupFeedEvent>, AppError> next = const Result.success([]);

  @override
  Future<Result<List<GroupFeedEvent>, AppError>> getGroupFeed(
    String groupId, {
    int limit = GroupRepository.defaultFeedLimit,
    String? afterId,
  }) async {
    fetches.add(afterId);
    return next;
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeRepo repo;
  late ProviderContainer container;
  late int leaderboardBuilds;
  late List<List<GroupFeedEvent>> emitted;

  void setUpContainer([List<GroupFeedEvent> initial = const []]) {
    repo = _FakeRepo()..next = Result.success(initial);
    leaderboardBuilds = 0;
    emitted = [];
    container = ProviderContainer(
      overrides: [
        groupRepositoryProvider.overrideWithValue(repo),
        dailyLeaderboardProvider('g-1', '2026-11-08').overrideWith((ref) async {
          leaderboardBuilds++;
          return const [];
        }),
      ],
    );
    container.listen(dailyLeaderboardProvider('g-1', '2026-11-08'), (_, _) {});
    container.listen(groupFeedProvider('g-1'), (_, next) {
      final value = next.valueOrNull;
      if (value != null) emitted.add(value);
    });
  }

  tearDown(() {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  test(
    'initial load, then a tick fetches id > lastId and prepends new rows',
    () {
      fakeAsync((async) {
        setUpContainer([_event(2), _event(1)]);
        async.flushMicrotasks();

        expect(repo.fetches, [null]);
        expect(emitted.last.map((e) => e.id), ['2', '1']);
        final buildsAfterLoad = leaderboardBuilds;

        repo.next = Result.success([_event(4), _event(3)]);
        async.elapse(feedPollInterval);

        expect(repo.fetches, [null, '2']);
        expect(emitted.last.map((e) => e.id), ['4', '3', '2', '1']);
        expect(leaderboardBuilds, buildsAfterLoad + 1);

        // A quiet tick changes nothing.
        repo.next = const Result.success([]);
        async.elapse(feedPollInterval);
        expect(repo.fetches, [null, '2', '4']);
        expect(emitted.last.map((e) => e.id), ['4', '3', '2', '1']);
        expect(leaderboardBuilds, buildsAfterLoad + 1);

        container.dispose();
      });
    },
  );

  test('a failed poll keeps the list', () {
    fakeAsync((async) {
      setUpContainer([_event(1)]);
      async.flushMicrotasks();

      repo.next = const Result.failure(AppError.network('offline'));
      async.elapse(feedPollInterval);

      expect(
        container.read(groupFeedProvider('g-1')).valueOrNull?.single.id,
        '1',
      );
      container.dispose();
    });
  });

  test('dispose cancels the timer', () {
    fakeAsync((async) {
      setUpContainer();
      async.flushMicrotasks();
      expect(async.periodicTimerCount, 1);

      container.dispose();

      expect(async.periodicTimerCount, 0);
      async.elapse(feedPollInterval * 3);
      expect(repo.fetches, [null]);
    });
  });

  test('paused stops polling; resumed polls at once and restarts', () {
    fakeAsync((async) {
      setUpContainer([_event(1)]);
      async.flushMicrotasks();

      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      expect(async.periodicTimerCount, 0);
      async.elapse(feedPollInterval * 3);
      expect(repo.fetches, [null]);

      repo.next = Result.success([_event(2)]);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      async.flushMicrotasks();
      expect(repo.fetches, [null, '1']);
      expect(emitted.last.map((e) => e.id), ['2', '1']);
      expect(async.periodicTimerCount, 1);

      repo.next = const Result.success([]);
      async.elapse(feedPollInterval);
      expect(repo.fetches, [null, '1', '2']);

      container.dispose();
    });
  });

  group('GroupFeedPoller back-off', () {
    test('20 empty polls slow to 60 s; 30 stop the timer', () {
      fakeAsync((async) {
        var polls = 0;
        final poller = GroupFeedPoller((_) async {
          polls++;
          return false;
        })..startFeedPolling('g-1');
        expect(poller.currentInterval, feedPollInterval);

        async.elapse(feedPollInterval * (feedPollSlowAfter - 1));
        expect(polls, feedPollSlowAfter - 1);
        expect(poller.currentInterval, feedPollInterval);

        async.elapse(feedPollInterval);
        expect(polls, feedPollSlowAfter);
        expect(poller.currentInterval, feedPollSlowInterval);
        expect(poller.isPolling, isTrue);

        // No poll fires at the old 15 s cadence any more.
        async.elapse(feedPollInterval);
        expect(polls, feedPollSlowAfter);

        async.elapse(
          feedPollSlowInterval * (feedPollStopAfter - feedPollSlowAfter),
        );
        expect(polls, feedPollStopAfter);
        expect(poller.isPolling, isFalse);
        expect(async.periodicTimerCount, 0);

        async.elapse(feedPollSlowInterval * 5);
        expect(polls, feedPollStopAfter);

        // Starting again resets the counters.
        poller.startFeedPolling('g-1');
        expect(poller.isPolling, isTrue);
        expect(poller.currentInterval, feedPollInterval);
        expect(poller.emptyPolls, 0);
        poller.stopFeedPolling();
      });
    });

    test('a poll with a new event resets to 15 s', () {
      fakeAsync((async) {
        var polls = 0;
        var fresh = false;
        final poller = GroupFeedPoller((_) async {
          polls++;
          return fresh;
        })..startFeedPolling('g-1');

        async.elapse(feedPollInterval * feedPollSlowAfter);
        expect(poller.currentInterval, feedPollSlowInterval);

        fresh = true;
        async.elapse(feedPollSlowInterval);
        expect(polls, feedPollSlowAfter + 1);
        expect(poller.currentInterval, feedPollInterval);
        expect(poller.emptyPolls, 0);

        fresh = false;
        async.elapse(feedPollInterval);
        expect(polls, feedPollSlowAfter + 2);
        expect(poller.emptyPolls, 1);
        poller.stopFeedPolling();
      });
    });

    test('resumed after a stop polls once and restarts at 15 s', () {
      fakeAsync((async) {
        var polls = 0;
        final poller = GroupFeedPoller((_) async {
          polls++;
          return false;
        })..startFeedPolling('g-1');
        async.elapse(
          feedPollInterval * feedPollSlowAfter +
              feedPollSlowInterval * (feedPollStopAfter - feedPollSlowAfter),
        );
        expect(poller.isPolling, isFalse);

        binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        async.flushMicrotasks();
        expect(polls, feedPollStopAfter + 1);
        expect(poller.isPolling, isTrue);
        expect(poller.currentInterval, feedPollInterval);
        expect(poller.emptyPolls, 1);
        poller.stopFeedPolling();
      });
    });
  });
}
