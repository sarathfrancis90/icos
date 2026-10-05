import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icos/core/constants/app_strings.dart';
import 'package:icos/features/groups/domain/models/group.dart';
import 'package:icos/features/groups/presentation/widgets/member_tile.dart';

import '../../../helpers/test_helpers.dart';

final _bob = GroupMember(
  id: 'm-2',
  groupId: 'g-1',
  userId: 'u-2',
  role: 'member',
  joinedAt: DateTime.utc(2026, 9, 1),
  displayName: 'Bob',
);

Widget _tile({
  bool isCurrentUser = false,
  bool isBlocked = false,
  bool viewerIsAdmin = false,
  void Function(MemberAction)? onAction,
  GroupMember? member,
}) {
  return buildTestWidget(
    Scaffold(
      body: MemberTile(
        member: member ?? _bob,
        isCurrentUser: isCurrentUser,
        isBlocked: isBlocked,
        viewerIsAdmin: viewerIsAdmin,
        onAction: onAction ?? (_) {},
      ),
    ),
  );
}

Future<void> _openMenu(WidgetTester tester, String userId) async {
  await tester.tap(find.byKey(Key('member_menu_$userId')));
  await tester.pumpAndSettle();
}

void main() {
  setUpTestEnvironment();

  group('MemberTile blocking', () {
    testWidgets('offers Report and Block for another member', (tester) async {
      await tester.pumpWidget(_tile());
      await _openMenu(tester, 'u-2');

      expect(find.text('Report user'), findsOneWidget);
      expect(find.text(AppStrings.blockUser), findsOneWidget);
      expect(find.byIcon(Icons.block_rounded), findsOneWidget);
      expect(find.text(AppStrings.unblockUser), findsNothing);
    });

    testWidgets('selecting Block reports MemberAction.block', (tester) async {
      MemberAction? picked;
      await tester.pumpWidget(_tile(onAction: (a) => picked = a));
      await _openMenu(tester, 'u-2');
      await tester.tap(find.text(AppStrings.blockUser));
      await tester.pumpAndSettle();

      expect(picked, MemberAction.block);
    });

    testWidgets('own row has no menu, so no Report or Block entries',
        (tester) async {
      await tester.pumpWidget(_tile(isCurrentUser: true));

      expect(find.byKey(const Key('member_menu_u-2')), findsNothing);
      expect(find.byType(PopupMenuButton<MemberAction>), findsNothing);
    });

    testWidgets('a blocked member shows "Blocked user" and Unblock',
        (tester) async {
      final semantics = tester.ensureSemantics();
      MemberAction? picked;
      await tester.pumpWidget(
        _tile(isBlocked: true, onAction: (a) => picked = a),
      );

      expect(find.text(AppStrings.blockedUserName), findsOneWidget);
      expect(find.text('Bob'), findsNothing);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.properties.label == AppStrings.blockedUserName,
        ),
        findsOneWidget,
      );

      await _openMenu(tester, 'u-2');
      expect(find.text(AppStrings.unblockUser), findsOneWidget);
      expect(find.text(AppStrings.blockUser), findsNothing);
      await tester.tap(find.text(AppStrings.unblockUser));
      await tester.pumpAndSettle();
      expect(picked, MemberAction.unblock);
      semantics.dispose();
    });

    testWidgets('admin keeps remove for a blocked member', (tester) async {
      await tester.pumpWidget(_tile(isBlocked: true, viewerIsAdmin: true));
      await _openMenu(tester, 'u-2');

      expect(find.text('Remove member'), findsOneWidget);
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
          child: _tile(isBlocked: true, viewerIsAdmin: true),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
