import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:icos/core/services/auth_session_provider.dart';
import 'package:icos/core/services/connectivity_service.dart';
import 'package:icos/core/services/edge_function_client.dart';
import 'package:icos/core/services/session_service.dart';
import 'package:icos/core/utils/app_error.dart';
import 'package:icos/core/utils/date_utils.dart';
import 'package:icos/core/utils/result.dart';
import 'package:icos/features/groups/domain/models/group.dart';
import 'package:icos/features/groups/presentation/group_detail_screen.dart';
import 'package:icos/features/groups/presentation/join_group_screen.dart';
import 'package:icos/features/groups/providers/groups_provider.dart';
import 'package:icos/features/puzzle/data/puzzle_repository.dart';
import 'package:icos/features/puzzle/data/puzzle_source.dart';
import 'package:icos/features/puzzle/data/submission_result.dart';
import 'package:icos/features/puzzle/presentation/puzzle_screen.dart';
import 'package:icos/features/puzzle/providers/daily_puzzle_provider.dart';

import '../../helpers/storage_test_helpers.dart';
import '../../helpers/test_helpers.dart';

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

class _JoiningGroups extends MyGroups {
  @override
  Future<List<Group>> build() async => const [];

  @override
  Future<Result<Group, AppError>> joinGroup(String inviteCode) async =>
      Result.success(_group);
}

class _Online extends ConnectivityNotifier {
  @override
  bool build() => true;
}

class _NoAttempts extends PuzzleRepository {
  _NoAttempts()
    : super(invoker: (fn, body) async => const EdgeResponse(500, {}));

  @override
  Future<SubmissionResult?> getOwnAttempt(String userId, String date) async =>
      null;
}

class _SignedIn implements SessionGateway {
  @override
  bool get hasSession => true;

  @override
  Future<void> signInAnonymously() async {}
}

String _location(GoRouter router) =>
    router.routerDelegate.currentConfiguration.last.matchedLocation;

GoRouter _router(String initial, Widget Function(String) screenFor) {
  return GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(path: '/', builder: (_, _) => const Text('HOME')),
      GoRoute(path: '/groups', builder: (_, _) => const Text('GROUPS TAB')),
      GoRoute(
        path: '/groups/:id',
        builder: (_, s) => GroupDetailScreen(groupId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/join/:code',
        builder: (_, s) =>
            JoinGroupScreen(inviteCode: s.pathParameters['code']!),
      ),
      GoRoute(
        path: '/puzzle/:date',
        builder: (_, s) => screenFor(s.pathParameters['date']!),
      ),
    ],
  );
}

void main() {
  setUpTestEnvironment();

  List<Override> groupOverrides({required bool signedIn}) => [
    groupsSessionProvider.overrideWith(
      (ref) => signedIn
          ? const GroupsSession(userId: 'u-1', isAnonymous: false)
          : const GroupsSession(userId: 'u-anon', isAnonymous: true),
    ),
    myGroupsProvider.overrideWith(_JoiningGroups.new),
    groupDetailProvider('g-1').overrideWith((ref) async => _group),
    groupMembersProvider('g-1').overrideWith((ref) async => const []),
    dailyLeaderboardProvider(
      'g-1',
      AppDateUtils.todayUtc(),
    ).overrideWith((ref) async => const []),
    weeklyLeaderboardProvider(
      'g-1',
      AppDateUtils.formatDate(AppDateUtils.weekStart()),
    ).overrideWith((ref) async => const []),
    groupFeedProvider('g-1').overrideWith((ref) => const Stream.empty()),
  ];

  Finder closeControl() => find.byTooltip('Back to Groups');

  testWidgets('/join/<code> as a guest on an empty stack offers a way out', (
    tester,
  ) async {
    final router = _router('/join/ABC123', (_) => const SizedBox());
    addTearDown(router.dispose);
    await tester.pumpWidget(
      buildTestWidgetWithRouter(
        router,
        overrides: groupOverrides(signedIn: false),
      ),
    );
    await tester.pumpAndSettle();

    expect(closeControl(), findsOneWidget);
    final size = tester.getSize(closeControl());
    expect(size.width, greaterThanOrEqualTo(44));
    expect(size.height, greaterThanOrEqualTo(44));

    await tester.tap(closeControl());
    await tester.pumpAndSettle();
    expect(_location(router), '/groups');
  });

  testWidgets('a successful join lands on the group with Groups underneath', (
    tester,
  ) async {
    final router = _router('/join/ABC123', (_) => const SizedBox());
    addTearDown(router.dispose);
    await tester.pumpWidget(
      buildTestWidgetWithRouter(
        router,
        overrides: groupOverrides(signedIn: true),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.byType(GroupDetailScreen), findsOneWidget);
    expect(_location(router), '/groups/g-1');
    expect(router.canPop(), isTrue);

    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('GROUPS TAB'), findsOneWidget);
  });

  testWidgets('/groups/<id> on an empty stack offers a way out', (
    tester,
  ) async {
    final router = _router('/groups/g-1', (_) => const SizedBox());
    addTearDown(router.dispose);
    await tester.pumpWidget(
      buildTestWidgetWithRouter(
        router,
        overrides: groupOverrides(signedIn: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(closeControl(), findsOneWidget);
    await tester.tap(closeControl());
    await tester.pumpAndSettle();
    expect(_location(router), '/groups');
  });

  testWidgets('/groups/<id> pushed over Groups keeps the normal back button', (
    tester,
  ) async {
    final router = _router('/groups', (_) => const SizedBox());
    addTearDown(router.dispose);
    await tester.pumpWidget(
      buildTestWidgetWithRouter(
        router,
        overrides: groupOverrides(signedIn: true),
      ),
    );
    await tester.pumpAndSettle();
    router.push('/groups/g-1');
    await tester.pumpAndSettle();

    expect(find.byType(BackButton), findsOneWidget);
    expect(closeControl(), findsNothing);
  });

  group('/puzzle/<date>', () {
    late Directory dir;
    setUp(() async => dir = await initTestStorage());
    tearDown(() async => dir.delete(recursive: true));

    testWidgets('on an empty stack the home button goes to /', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final today = AppDateUtils.todayUtc();
      final puzzle = smallTestPuzzle.copyWith(puzzleDate: today);
      final router = _router(
        '/puzzle/$today',
        (date) => PuzzleScreen(source: PuzzleSource.forDate(date)),
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        buildTestWidgetWithRouter(
          router,
          overrides: [
            puzzleForDateProvider(today).overrideWith((ref) async => puzzle),
            puzzleRepositoryProvider.overrideWithValue(_NoAttempts()),
            authSessionProvider.overrideWithValue(const FakeAuthSessionInfo()),
            connectivityNotifierProvider.overrideWith(_Online.new),
            edgeInvokerProvider.overrideWithValue(
              (fn, body) async => const EdgeResponse(200, {'nonce': 'n'}),
            ),
            sessionEnsurerProvider.overrideWithValue(
              SessionEnsurer(gateway: _SignedIn()),
            ),
          ],
        ),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      final back = find.bySemanticsLabel('Go back');
      expect(back, findsOneWidget);
      await tester.tap(back);
      await tester.pumpAndSettle();
      expect(_location(router), '/');
      await tester.pumpWidget(const SizedBox());
    });
  });
}
