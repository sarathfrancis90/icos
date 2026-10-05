import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icos/core/utils/app_error.dart';
import 'package:icos/core/utils/result.dart';
import 'package:icos/features/groups/data/group_repository.dart';
import 'package:icos/features/groups/domain/models/blocked_user.dart';
import 'package:icos/features/groups/providers/blocked_users_provider.dart';
import 'package:icos/features/groups/providers/groups_provider.dart';
import 'package:mocktail/mocktail.dart';

class _MockRepo extends Mock implements GroupRepository {}

final _bob = BlockedUser(
  userId: 'u-2',
  displayName: 'Bob',
  blockedAt: DateTime.utc(2026, 10, 5),
);

void main() {
  late _MockRepo repo;
  late ProviderContainer container;
  var blocked = <BlockedUser>[];
  var leaderboardBuilds = 0;

  setUp(() {
    repo = _MockRepo();
    blocked = [];
    leaderboardBuilds = 0;
    when(
      () => repo.listBlockedUsers(),
    ).thenAnswer((_) async => Result.success(List.of(blocked)));
    container = ProviderContainer(
      overrides: [
        groupRepositoryProvider.overrideWithValue(repo),
        groupsSessionProvider.overrideWith(
          (ref) => const GroupsSession(userId: 'u-1', isAnonymous: false),
        ),
      ],
    );
    addTearDown(container.dispose);
  });

  test('loads the blocked list and exposes the id set', () async {
    blocked = [_bob];
    final list = await container.read(blockedUsersProvider.future);
    expect(list.single.userId, 'u-2');
    expect(container.read(blockedUserIdsProvider), {'u-2'});
  });

  test('is empty and skips the network when signed out', () async {
    final signedOut = ProviderContainer(
      overrides: [
        groupRepositoryProvider.overrideWithValue(repo),
        groupsSessionProvider.overrideWith(
          (ref) => const GroupsSession.signedOut(),
        ),
      ],
    );
    addTearDown(signedOut.dispose);
    expect(await signedOut.read(blockedUsersProvider.future), isEmpty);
    verifyNever(() => repo.listBlockedUsers());
  });

  test(
    'block refreshes the list and invalidates server-filtered data',
    () async {
      when(() => repo.blockUser('u-2')).thenAnswer((_) async {
        blocked = [_bob];
        return const Result.success(null);
      });
      when(() => repo.getGroupDailyLeaderboard(any(), any())).thenAnswer((
        _,
      ) async {
        leaderboardBuilds++;
        return const Result.success([]);
      });
      await container.read(blockedUsersProvider.future);
      final sub = container.listen(
        dailyLeaderboardProvider('g', '2026-10-05'),
        (_, _) {},
      );
      addTearDown(sub.close);
      await container.read(dailyLeaderboardProvider('g', '2026-10-05').future);
      expect(leaderboardBuilds, 1);

      final result = await container
          .read(blockedUsersProvider.notifier)
          .block('u-2');

      expect(result, isA<Success<void, AppError>>());
      expect(container.read(blockedUserIdsProvider), {'u-2'});
      await container.read(dailyLeaderboardProvider('g', '2026-10-05').future);
      expect(leaderboardBuilds, 2);
    },
  );

  test(
    'block failure leaves the list untouched and returns the error',
    () async {
      when(() => repo.blockUser('u-2')).thenAnswer(
        (_) async => const Result.failure(AppError.database('nope')),
      );
      await container.read(blockedUsersProvider.future);

      final result = await container
          .read(blockedUsersProvider.notifier)
          .block('u-2');

      expect(result, isA<Failure<void, AppError>>());
      expect(container.read(blockedUserIdsProvider), isEmpty);
    },
  );

  test('unblock removes the user from the list', () async {
    blocked = [_bob];
    when(() => repo.unblockUser('u-2')).thenAnswer((_) async {
      blocked = [];
      return const Result.success(null);
    });
    await container.read(blockedUsersProvider.future);

    final result = await container
        .read(blockedUsersProvider.notifier)
        .unblock('u-2');

    expect(result, isA<Success<void, AppError>>());
    expect(container.read(blockedUserIdsProvider), isEmpty);
  });

  test('a failed refetch after block keeps the id blocked', () async {
    var listCalls = 0;
    when(() => repo.listBlockedUsers()).thenAnswer((_) async {
      listCalls++;
      return listCalls == 1
          ? const Result.success(<BlockedUser>[])
          : const Result.failure(AppError.network('offline'));
    });
    when(() => repo.blockUser('u-2'))
        .thenAnswer((_) async => const Result.success(null));
    await container.read(blockedUsersProvider.future);

    final result = await container.read(blockedUsersProvider.notifier).block('u-2');

    expect(result, isA<Success<void, AppError>>());
    expect(container.read(blockedUsersProvider).hasError, isFalse);
    expect(container.read(blockedUserIdsProvider), {'u-2'});
  });

  test('a failed refetch after unblock keeps the id unblocked', () async {
    var listCalls = 0;
    when(() => repo.listBlockedUsers()).thenAnswer((_) async {
      listCalls++;
      return listCalls == 1
          ? Result.success([_bob])
          : const Result.failure(AppError.network('offline'));
    });
    when(() => repo.unblockUser('u-2'))
        .thenAnswer((_) async => const Result.success(null));
    await container.read(blockedUsersProvider.future);

    await container.read(blockedUsersProvider.notifier).unblock('u-2');

    expect(container.read(blockedUserIdsProvider), isEmpty);
  });
}
