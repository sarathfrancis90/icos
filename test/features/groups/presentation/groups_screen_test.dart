import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icos/core/constants/app_strings.dart';
import 'package:icos/features/groups/domain/models/group.dart';
import 'package:icos/features/groups/presentation/groups_screen.dart';
import 'package:icos/features/groups/presentation/widgets/account_required_card.dart';
import 'package:icos/features/groups/providers/groups_provider.dart';

import '../../../helpers/test_helpers.dart';

class _FakeMyGroups extends MyGroups {
  _FakeMyGroups(this.groups);

  final List<Group> groups;

  @override
  Future<List<Group>> build() async => groups;
}

const _signedIn = GroupsSession(userId: 'u-1', isAnonymous: false);
const _anonymous = GroupsSession(userId: 'u-anon', isAnonymous: true);

final _group = Group(
  id: 'g-1',
  name: 'Sunday Solvers',
  description: 'Family group',
  inviteCode: 'ABC123',
  adminId: 'u-1',
  memberCount: 3,
  maxMembers: 50,
  isActive: true,
  createdAt: DateTime.utc(2026, 9, 1),
);

Widget _build({
  GroupsSession session = _signedIn,
  List<Group> groups = const [],
}) {
  return buildTestWidget(
    const Scaffold(body: GroupsScreen()),
    overrides: [
      groupsSessionProvider.overrideWith((ref) => session),
      myGroupsProvider.overrideWith(() => _FakeMyGroups(groups)),
    ],
  );
}

void main() {
  setUpTestEnvironment();

  group('GroupsScreen', () {
    testWidgets('shows empty state with create/join CTAs', (tester) async {
      await tester.pumpWidget(_build());
      await tester.pumpAndSettle();

      expect(find.text(GroupsScreen.emptyMessage), findsOneWidget);
      expect(find.byKey(const Key('groups_empty_create')), findsOneWidget);
      expect(find.byKey(const Key('groups_empty_join')), findsOneWidget);
      expect(find.byType(AccountRequiredCard), findsNothing);
    });

    testWidgets('gates anonymous users with account CTA', (tester) async {
      await tester.pumpWidget(_build(session: _anonymous));
      await tester.pumpAndSettle();

      expect(find.byType(AccountRequiredCard), findsOneWidget);
      expect(find.text(AccountRequiredCard.ctaLabel), findsOneWidget);
      expect(find.text(GroupsScreen.emptyMessage), findsNothing);
      expect(find.byKey(const Key('groups_empty_create')), findsNothing);
    });

    testWidgets('lists groups with member count', (tester) async {
      await tester.pumpWidget(_build(groups: [_group]));
      await tester.pumpAndSettle();

      expect(find.text('Sunday Solvers'), findsOneWidget);
      expect(find.text('Family group'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text(GroupsScreen.emptyMessage), findsNothing);
      expect(find.byType(RefreshIndicator), findsOneWidget);
    });

    group('create dialog validation', () {
      Future<void> openDialog(WidgetTester tester) async {
        await tester.pumpWidget(_build());
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('groups_empty_create')));
        await tester.pumpAndSettle();
        expect(find.text(AppStrings.createGroup), findsWidgets);
      }

      testWidgets('rejects empty name', (tester) async {
        await openDialog(tester);
        await tester.tap(find.byKey(const Key('create_group_submit')));
        await tester.pumpAndSettle();

        expect(find.text('Please enter a group name'), findsOneWidget);
        expect(find.byType(AlertDialog), findsOneWidget);
      });

      testWidgets('rejects a one-character name', (tester) async {
        await openDialog(tester);
        await tester.enterText(find.byKey(const Key('create_group_name')), 'a');
        await tester.tap(find.byKey(const Key('create_group_submit')));
        await tester.pumpAndSettle();

        expect(find.text('Must be at least 2 characters'), findsOneWidget);
        expect(find.byType(AlertDialog), findsOneWidget);
      });

      testWidgets('rejects profanity', (tester) async {
        await openDialog(tester);
        await tester.enterText(
          find.byKey(const Key('create_group_name')),
          'sh1t crew',
        );
        await tester.tap(find.byKey(const Key('create_group_submit')));
        await tester.pumpAndSettle();

        expect(find.text('This name is not allowed'), findsOneWidget);
        expect(find.byType(AlertDialog), findsOneWidget);
      });

      testWidgets('cancel closes the dialog', (tester) async {
        await openDialog(tester);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsNothing);
      });
    });

    testWidgets('join dialog validates code length', (tester) async {
      await tester.pumpWidget(_build());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('groups_empty_join')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('join_group_code')), 'ab1');
      await tester.tap(find.byKey(const Key('join_group_submit')));
      await tester.pumpAndSettle();

      expect(find.textContaining('6-character'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
    });
  });
}
