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
  _FakeRepo(this.current, {this.fail = false});

  Group current;
  final bool fail;
  final regenerated = <String>[];

  @override
  Future<Result<List<Group>, AppError>> getMyGroups() async =>
      Result.success([current]);

  @override
  Future<Result<Group, AppError>> regenerateInviteCode(String groupId) async {
    regenerated.add(groupId);
    if (fail) return const Result.failure(AppError.network('No connection'));
    current = Group(
      id: current.id,
      name: current.name,
      description: '',
      inviteCode: 'NEW456',
      adminId: current.adminId,
      memberCount: current.memberCount,
      maxMembers: 50,
      isActive: true,
      createdAt: current.createdAt,
    );
    return Result.success(current);
  }
}

Group _group() => Group(
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

Widget _build(_FakeRepo repo, {String userId = 'u-1'}) {
  return buildTestWidget(
    const GroupDetailScreen(groupId: 'g-1'),
    overrides: [
      groupRepositoryProvider.overrideWithValue(repo),
      groupsSessionProvider.overrideWith(
        (ref) => GroupsSession(userId: userId, isAnonymous: false),
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
      groupFeedProvider('g-1').overrideWith((ref) => Stream.value(const [])),
    ],
  );
}

Future<void> _openMenu(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('group_menu')));
  await tester.pumpAndSettle();
}

void main() {
  setUpTestEnvironment();

  group('New invite code', () {
    testWidgets('is hidden from non-admins', (tester) async {
      await tester.pumpWidget(_build(_FakeRepo(_group()), userId: 'u-2'));
      await _openMenu(tester);

      expect(find.text(AppStrings.newInviteCode), findsNothing);
    });

    testWidgets('admin confirms, repo is called and the new code shows', (
      tester,
    ) async {
      final repo = _FakeRepo(_group());
      await tester.pumpWidget(_build(repo));
      await _openMenu(tester);

      await tester.tap(find.text(AppStrings.newInviteCode));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.newInviteCodeConfirm), findsOneWidget);
      await tester.tap(find.text(AppStrings.newInviteCodeGenerate));
      await tester.pumpAndSettle();

      expect(repo.regenerated, ['g-1']);
      expect(find.text('New invite code: NEW456'), findsOneWidget);
      expect(find.text('NEW456'), findsOneWidget);
      expect(find.text('ABC123'), findsNothing);
    });

    testWidgets('cancel does not call the repo', (tester) async {
      final repo = _FakeRepo(_group());
      await tester.pumpWidget(_build(repo));
      await _openMenu(tester);

      await tester.tap(find.text(AppStrings.newInviteCode));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(repo.regenerated, isEmpty);
      expect(find.text('ABC123'), findsOneWidget);
    });

    testWidgets('failure shows an error SnackBar and keeps the old code', (
      tester,
    ) async {
      final repo = _FakeRepo(_group(), fail: true);
      await tester.pumpWidget(_build(repo));
      await _openMenu(tester);

      await tester.tap(find.text(AppStrings.newInviteCode));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.newInviteCodeGenerate));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('New invite code:'), findsNothing);
      expect(find.text('ABC123'), findsOneWidget);
    });
  });
}
