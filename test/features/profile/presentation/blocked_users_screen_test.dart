import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icos/core/constants/app_strings.dart';
import 'package:icos/core/utils/app_error.dart';
import 'package:icos/core/utils/result.dart';
import 'package:icos/features/groups/domain/models/blocked_user.dart';
import 'package:icos/features/groups/providers/blocked_users_provider.dart';
import 'package:icos/features/profile/presentation/blocked_users_screen.dart';

import '../../../helpers/test_helpers.dart';

BlockedUser _user(String id, String name) => BlockedUser(
  userId: id,
  displayName: name,
  blockedAt: DateTime.utc(2026, 10, 5),
);

class _FakeBlockedUsers extends BlockedUsers {
  _FakeBlockedUsers(this.users, {this.failFirstLoad = false});

  final List<BlockedUser> users;
  final bool failFirstLoad;
  final unblocked = <String>[];
  var builds = 0;

  @override
  Future<List<BlockedUser>> build() async {
    builds++;
    if (failFirstLoad && builds == 1) {
      throw const AppError.network('No connection');
    }
    return users;
  }

  @override
  Future<Result<void, AppError>> unblock(String userId) async {
    unblocked.add(userId);
    state = AsyncValue.data(users.where((u) => u.userId != userId).toList());
    return const Result.success(null);
  }
}

Widget _build(_FakeBlockedUsers fake) => buildTestWidget(
  const BlockedUsersScreen(),
  overrides: [blockedUsersProvider.overrideWith(() => fake)],
);

void main() {
  setUpTestEnvironment();

  group('BlockedUsersScreen', () {
    testWidgets('lists blocked users with an Unblock button', (tester) async {
      await tester.pumpWidget(
        _build(_FakeBlockedUsers([_user('u-2', 'Bob'), _user('u-3', 'Cara')])),
      );
      await tester.pumpAndSettle();

      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Cara'), findsOneWidget);
      expect(find.text(AppStrings.unblockButton), findsNWidgets(2));
      final size = tester.getSize(find.byType(TextButton).first);
      expect(size.height, greaterThanOrEqualTo(44));
      expect(size.width, greaterThanOrEqualTo(44));
    });

    testWidgets('Unblock calls the notifier and removes the row', (
      tester,
    ) async {
      final fake = _FakeBlockedUsers([_user('u-2', 'Bob')]);
      await tester.pumpWidget(_build(fake));
      await tester.pumpAndSettle();

      await tester.tap(find.text(AppStrings.unblockButton));
      await tester.pumpAndSettle();

      expect(fake.unblocked, ['u-2']);
      expect(find.text('Bob'), findsNothing);
      expect(find.text(AppStrings.noBlockedUsers), findsOneWidget);
    });

    testWidgets('shows the empty state', (tester) async {
      await tester.pumpWidget(_build(_FakeBlockedUsers(const [])));
      await tester.pumpAndSettle();

      expect(find.text("You haven't blocked anyone."), findsOneWidget);
    });

    testWidgets('shows an error with a working Retry', (tester) async {
      final fake = _FakeBlockedUsers([
        _user('u-2', 'Bob'),
      ], failFirstLoad: true);
      await tester.pumpWidget(_build(fake));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.blockedUsersLoadFailed), findsOneWidget);
      await tester.tap(find.text(AppStrings.retry));
      await tester.pumpAndSettle();

      expect(find.text('Bob'), findsOneWidget);
      expect(find.text(AppStrings.blockedUsersLoadFailed), findsNothing);
    });

    testWidgets('no overflow at 2x text on a 320x568 screen', (tester) async {
      tester.view
        ..physicalSize = const Size(320, 568)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 568),
            textScaler: TextScaler.linear(2),
          ),
          child: _build(
            _FakeBlockedUsers([
              _user('u-2', 'A rather long display name indeed'),
            ]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
