import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icos/core/constants/app_strings.dart';
import 'package:icos/core/utils/app_error.dart';
import 'package:icos/core/utils/date_utils.dart';
import 'package:icos/core/utils/result.dart';
import 'package:icos/features/groups/data/group_repository.dart';
import 'package:icos/features/groups/domain/models/group.dart';
import 'package:icos/features/groups/presentation/group_detail_screen.dart';
import 'package:icos/features/groups/providers/groups_provider.dart';

import '../../../helpers/test_helpers.dart';

class _FakeRepo extends GroupRepository {
  _FakeRepo(this.groups);

  List<Group> groups;
  int fetches = 0;

  @override
  Future<Result<List<Group>, AppError>> getMyGroups() async {
    fetches++;
    return Result.success(groups);
  }
}

Group _group({int members = 1}) => Group(
  id: 'g-1',
  name: 'Sunday Solvers',
  description: '',
  inviteCode: 'ABC123',
  adminId: 'u-1',
  memberCount: members,
  maxMembers: 50,
  isActive: true,
  createdAt: DateTime.utc(2026, 9, 1),
);

GroupFeedEvent _event(String id) => GroupFeedEvent(
  id: id,
  groupId: 'g-1',
  userId: 'u-2',
  event: 'member_joined',
  createdAt: DateTime.utc(2026, 10, 1),
);

Widget _build(_FakeRepo repo, StreamController<List<GroupFeedEvent>> feed) {
  return buildTestWidget(
    Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const GroupDetailScreen(groupId: 'g-1'),
            ),
          ),
          child: const Text('open'),
        ),
      ),
    ),
    overrides: [
      groupRepositoryProvider.overrideWithValue(repo),
      groupsSessionProvider.overrideWith(
        (ref) => const GroupsSession(userId: 'u-2', isAnonymous: false),
      ),
      groupMembersProvider('g-1').overrideWith((ref) async => const []),
      dailyLeaderboardProvider(
        'g-1',
        AppDateUtils.todayUtc(),
      ).overrideWith((ref) async => const []),
      weeklyLeaderboardProvider(
        'g-1',
        AppDateUtils.formatDate(AppDateUtils.weekStart()),
      ).overrideWith((ref) async => const []),
      groupFeedProvider('g-1').overrideWith((ref) => feed.stream),
    ],
  );
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  setUpTestEnvironment();

  testWidgets('opening the screen refreshes the member count', (tester) async {
    final repo = _FakeRepo([_group()]);
    final feed = StreamController<List<GroupFeedEvent>>();
    addTearDown(feed.close);
    await tester.pumpWidget(_build(repo, feed));
    // Prime the cached list with a stale count.
    final container = ProviderScope.containerOf(
      tester.element(find.text('open')),
    );
    await container.read(myGroupsProvider.future);
    expect(container.read(myGroupsProvider).value!.single.memberCount, 1);
    final before = repo.fetches;

    repo.groups = [_group(members: 2)];
    await _open(tester);

    expect(repo.fetches, greaterThan(before));
    expect(container.read(myGroupsProvider).value!.single.memberCount, 2);
    expect(find.textContaining('2/50'), findsWidgets);
  });

  testWidgets('a new feed event refreshes the group row', (tester) async {
    final repo = _FakeRepo([_group()]);
    final feed = StreamController<List<GroupFeedEvent>>();
    addTearDown(feed.close);
    await tester.pumpWidget(_build(repo, feed));
    await _open(tester);
    feed.add([_event('e-1')]);
    await tester.pumpAndSettle();
    final before = repo.fetches;

    repo.groups = [_group(members: 3)];
    feed.add([_event('e-2'), _event('e-1')]);
    await tester.pumpAndSettle();

    expect(repo.fetches, greaterThan(before));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(GroupDetailScreen)),
    );
    expect(container.read(myGroupsProvider).value!.single.memberCount, 3);
  });

  testWidgets('a group the user was removed from pops with a SnackBar', (
    tester,
  ) async {
    final repo = _FakeRepo([_group()]);
    final feed = StreamController<List<GroupFeedEvent>>();
    addTearDown(feed.close);
    await tester.pumpWidget(_build(repo, feed));
    final container = ProviderScope.containerOf(
      tester.element(find.text('open')),
    );
    await container.read(myGroupsProvider.future);

    repo.groups = const [];
    await _open(tester);

    expect(find.byType(GroupDetailScreen), findsNothing);
    expect(find.text(AppStrings.groupNoLongerMember), findsOneWidget);
  });
}
