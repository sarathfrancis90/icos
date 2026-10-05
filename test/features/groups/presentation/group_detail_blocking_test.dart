import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icos/core/constants/app_strings.dart';
import 'package:icos/core/utils/app_error.dart';
import 'package:icos/core/utils/date_utils.dart';
import 'package:icos/core/utils/result.dart';
import 'package:icos/features/groups/domain/models/blocked_user.dart';
import 'package:icos/features/groups/domain/models/group.dart';
import 'package:icos/features/groups/presentation/group_detail_screen.dart';
import 'package:icos/features/groups/providers/blocked_users_provider.dart';
import 'package:icos/features/groups/providers/groups_provider.dart';

import '../../../helpers/test_helpers.dart';

class _FakeBlockedUsers extends BlockedUsers {
  _FakeBlockedUsers(this.initial, {this.failWith});

  final List<BlockedUser> initial;
  final AppError? failWith;
  final blocked = <String>[];
  final unblocked = <String>[];

  @override
  Future<List<BlockedUser>> build() async => initial;

  @override
  Future<Result<void, AppError>> block(String userId) async {
    blocked.add(userId);
    if (failWith != null) return Result.failure(failWith!);
    state = AsyncValue.data([
      BlockedUser(
        userId: userId,
        displayName: 'Bob',
        blockedAt: DateTime.utc(2026, 10, 5),
      ),
    ]);
    return const Result.success(null);
  }

  @override
  Future<Result<void, AppError>> unblock(String userId) async {
    unblocked.add(userId);
    state = const AsyncValue.data([]);
    return const Result.success(null);
  }
}

final _group = Group(
  id: 'g-1',
  name: 'Sunday Solvers',
  description: '',
  inviteCode: 'ABC123',
  adminId: 'u-1',
  memberCount: 2,
  maxMembers: 50,
  isActive: true,
  createdAt: DateTime.utc(2026, 9, 1),
);

GroupMember _member(String id, String name, {String role = 'member'}) =>
    GroupMember(
      id: 'm-$id',
      groupId: 'g-1',
      userId: id,
      role: role,
      joinedAt: DateTime.utc(2026, 9, 1),
      displayName: name,
    );

Widget _build(_FakeBlockedUsers fake) {
  return buildTestWidget(
    const GroupDetailScreen(groupId: 'g-1'),
    overrides: [
      groupsSessionProvider.overrideWith(
        (ref) => const GroupsSession(userId: 'u-1', isAnonymous: false),
      ),
      groupDetailProvider('g-1').overrideWith((ref) async => _group),
      groupMembersProvider('g-1').overrideWith(
        (ref) async => [
          _member('u-1', 'Alice', role: 'admin'),
          _member('u-2', 'Bob'),
        ],
      ),
      dailyLeaderboardProvider(
        'g-1',
        AppDateUtils.todayUtc(),
      ).overrideWith((ref) async => const []),
      weeklyLeaderboardProvider(
        'g-1',
        AppDateUtils.formatDate(AppDateUtils.weekStart()),
      ).overrideWith((ref) async => const []),
      groupFeedProvider('g-1').overrideWith((ref) => Stream.value(const [])),
      blockedUsersProvider.overrideWith(() => fake),
    ],
  );
}

Future<void> _openMembers(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.tap(find.text(AppStrings.groupMembers));
  await tester.pumpAndSettle();
}

void main() {
  setUpTestEnvironment();

  group('GroupDetailScreen blocking', () {
    testWidgets('block entry is on other members, not on the own row', (
      tester,
    ) async {
      await tester.pumpWidget(_build(_FakeBlockedUsers(const [])));
      await _openMembers(tester);

      expect(find.byKey(const Key('member_menu_u-2')), findsOneWidget);
      expect(find.byKey(const Key('member_menu_u-1')), findsNothing);
      await tester.tap(find.byKey(const Key('member_menu_u-2')));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.blockUser), findsOneWidget);
    });

    testWidgets('confirm dialog shows the copy and confirming blocks', (
      tester,
    ) async {
      final fake = _FakeBlockedUsers(const []);
      await tester.pumpWidget(_build(fake));
      await _openMembers(tester);

      await tester.tap(find.byKey(const Key('member_menu_u-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.blockUser));
      await tester.pumpAndSettle();

      expect(find.text('Block Bob?'), findsOneWidget);
      expect(
        find.text(
          "You won't see their scores or activity in any group. They won't be "
          "told. We'll also be notified so we can review their account.",
        ),
        findsOneWidget,
      );
      expect(find.text('Cancel'), findsOneWidget);
      expect(fake.blocked, isEmpty);

      await tester.tap(find.widgetWithText(FilledButton, 'Block'));
      await tester.pumpAndSettle();

      expect(fake.blocked, ['u-2']);
      expect(find.text('Bob blocked'), findsOneWidget);
      // The row now shows as blocked.
      expect(find.text(AppStrings.blockedUserName), findsOneWidget);
    });

    testWidgets('cancelling the dialog does not block', (tester) async {
      final fake = _FakeBlockedUsers(const []);
      await tester.pumpWidget(_build(fake));
      await _openMembers(tester);

      await tester.tap(find.byKey(const Key('member_menu_u-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.blockUser));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(fake.blocked, isEmpty);
    });

    testWidgets('a failed block shows the error message', (tester) async {
      final fake = _FakeBlockedUsers(
        const [],
        failWith: const AppError.validation('You cannot block yourself'),
      );
      await tester.pumpWidget(_build(fake));
      await _openMembers(tester);

      await tester.tap(find.byKey(const Key('member_menu_u-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.blockUser));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Block'));
      await tester.pumpAndSettle();

      expect(find.text('You cannot block yourself'), findsOneWidget);
    });

    testWidgets('a blocked member shows Unblock, which needs no confirmation', (
      tester,
    ) async {
      final fake = _FakeBlockedUsers([
        BlockedUser(
          userId: 'u-2',
          displayName: 'Bob',
          blockedAt: DateTime.utc(2026, 10, 5),
        ),
      ]);
      await tester.pumpWidget(_build(fake));
      await _openMembers(tester);

      expect(find.text(AppStrings.blockedUserName), findsOneWidget);
      expect(find.text('Bob'), findsNothing);

      await tester.tap(find.byKey(const Key('member_menu_u-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.unblockUser));
      await tester.pumpAndSettle();

      expect(fake.unblocked, ['u-2']);
      expect(find.text('Bob unblocked'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
    });
  });
}
