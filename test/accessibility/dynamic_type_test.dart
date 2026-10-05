import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:icos/core/constants/app_strings.dart';
import 'package:icos/core/services/auth_session_provider.dart';
import 'package:icos/core/services/connectivity_service.dart';
import 'package:icos/core/services/edge_function_client.dart';
import 'package:icos/core/services/session_service.dart';
import 'package:icos/core/utils/date_utils.dart';
import 'package:icos/features/auth/domain/auth_strategy.dart';
import 'package:icos/features/auth/presentation/auth_screen.dart';
import 'package:icos/features/auth/providers/auth_provider.dart';
import 'package:icos/features/groups/domain/models/group.dart';
import 'package:icos/features/groups/presentation/groups_screen.dart';
import 'package:icos/features/groups/providers/groups_provider.dart';
import 'package:icos/features/profile/presentation/widgets/guest_account_card.dart';
import 'package:icos/features/puzzle/data/puzzle_repository.dart';
import 'package:icos/features/puzzle/data/puzzle_source.dart';
import 'package:icos/features/puzzle/data/submission_result.dart';
import 'package:icos/features/puzzle/presentation/puzzle_screen.dart';
import 'package:icos/features/puzzle/providers/daily_puzzle_provider.dart';
import 'package:icos/features/stats/presentation/stats_screen.dart';
import 'package:icos/shared/widgets/text_scale_limit.dart';
import 'package:icos/features/stats/providers/stats_provider.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import '../helpers/storage_test_helpers.dart';
import '../helpers/test_helpers.dart';

/// The layouts are verified to 200% text scale on the smallest supported
/// phone (320x568) and a current one (393x852).
const _sizes = [Size(320, 568), Size(393, 852)];
const _scale = 2.0;

Future<void> _pump(WidgetTester tester, Size size, Widget app) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = _scale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(app);
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Every [texts] entry is on screen with a real size, horizontally inside the
/// screen (and vertically too when [checkVertical]).
void _expectLaidOut(
  WidgetTester tester,
  Size screen,
  List<String> texts, {
  bool checkVertical = true,
}) {
  for (final text in texts) {
    final finder = find.textContaining(text);
    expect(finder, findsWidgets, reason: '"$text" is missing');
    final rect = tester.getRect(finder.first);
    expect(rect.width, greaterThan(0), reason: '"$text" has no width');
    expect(rect.height, greaterThan(0), reason: '"$text" has no height');
    expect(rect.left, greaterThanOrEqualTo(-0.5), reason: '"$text" left');
    expect(
      rect.right,
      lessThanOrEqualTo(screen.width + 0.5),
      reason: '"$text" runs off the right edge: $rect',
    );
    if (checkVertical) {
      expect(rect.top, greaterThanOrEqualTo(-0.5), reason: '"$text" top');
      expect(
        rect.bottom,
        lessThanOrEqualTo(screen.height + 0.5),
        reason: '"$text" runs off the bottom: $rect',
      );
    }
  }
}

/// Fails with the full error (it names the offending widget) when the frame
/// threw, e.g. a RenderFlex overflow.
void _expectNoException(WidgetTester tester) {
  final error = tester.takeException();
  if (error != null) {
    fail(error is FlutterError ? error.toStringDeep() : '$error');
  }
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

class _FakeAuth extends AuthNotifier {
  @override
  AsyncValue<User?> build() => const AsyncValue.data(null);
}

class _FakeMyGroups extends MyGroups {
  @override
  Future<List<Group>> build() async => [
    Group(
      id: 'g-1',
      name: 'Sunday Solvers',
      description: '',
      inviteCode: 'ABC123',
      adminId: 'u-1',
      memberCount: 3,
      maxMembers: 50,
      isActive: true,
      createdAt: DateTime.utc(2026, 9, 1),
    ),
  ];
}

void main() {
  setUpTestEnvironment();

  late Directory dir;
  setUp(() async => dir = await initTestStorage());
  tearDown(() async => dir.delete(recursive: true));

  group('TextScaleLimit', () {
    Future<double> scaleSeenAt(WidgetTester tester, double system) async {
      tester.platformDispatcher.textScaleFactorTestValue = system;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      late double seen;
      await tester.pumpWidget(
        MaterialApp(
          home: TextScaleLimit(
            child: Builder(
              builder: (context) {
                seen = MediaQuery.textScalerOf(context).scale(10) / 10;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      return seen;
    }

    testWidgets('clamps system sizes beyond 200%', (tester) async {
      expect(await scaleSeenAt(tester, 3.1), 2.0);
    });

    testWidgets('leaves sizes up to 200% alone', (tester) async {
      expect(await scaleSeenAt(tester, 1.5), 1.5);
      expect(await scaleSeenAt(tester, 2.0), 2.0);
    });
  });

  for (final size in _sizes) {
    final tag = '${size.width.toInt()}x${size.height.toInt()} at 200%';

    testWidgets('puzzle HUD reflows ($tag)', (tester) async {
      final today = AppDateUtils.todayUtc();
      final puzzle = smallTestPuzzle.copyWith(puzzleDate: today);
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => PuzzleScreen(source: PuzzleSource.daily(today)),
          ),
        ],
      );
      addTearDown(router.dispose);
      await _pump(
        tester,
        size,
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

      _expectNoException(tester);
      _expectLaidOut(tester, size, [
        '00:00',
        '3x3',
        'Easy',
        'Par',
        'Reset',
        'Hint',
      ]);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('groups header reflows ($tag)', (tester) async {
      await _pump(
        tester,
        size,
        buildTestWidget(
          const Scaffold(body: GroupsScreen()),
          overrides: [
            groupsSessionProvider.overrideWith(
              (ref) => const GroupsSession(userId: 'u-1', isAnonymous: false),
            ),
            myGroupsProvider.overrideWith(_FakeMyGroups.new),
          ],
        ),
      );

      _expectNoException(tester);
      _expectLaidOut(tester, size, ['Groups', 'Sunday Solvers']);
      for (final tip in ['Create Group', 'Join Group']) {
        final rect = tester.getRect(find.bySemanticsLabel(tip).first);
        expect(
          rect.right,
          lessThanOrEqualTo(size.width + 0.5),
          reason: '$tip button is pushed off screen',
        );
        expect(rect.left, greaterThanOrEqualTo(0));
      }
    });

    testWidgets('stats cards reflow ($tag)', (tester) async {
      await _pump(
        tester,
        size,
        buildTestWidget(
          const Scaffold(body: StatsScreen()),
          overrides: [
            statsOverviewProvider.overrideWith(
              (ref) async => const StatsOverview(
                currentStreak: 12,
                longestStreak: 34,
                totalSolved: 56,
                averageTimeSeconds: 139,
                freezeCount: 1,
                lastFreezeUsedAt: null,
              ),
            ),
            solveHistoryProvider.overrideWith((ref) async => const []),
          ],
        ),
      );

      _expectNoException(tester);
      _expectLaidOut(tester, size, [
        'Statistics',
        'Current Streak',
        'Longest Streak',
      ], checkVertical: false);
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pump();
      _expectNoException(tester);
      _expectLaidOut(tester, size, [
        'Puzzles Solved',
        'Average Time',
        '02:19',
      ], checkVertical: false);
    });

    testWidgets('profile guest card reflows ($tag)', (tester) async {
      await _pump(
        tester,
        size,
        buildTestWidget(
          const Scaffold(
            body: SingleChildScrollView(
              padding: EdgeInsetsDirectional.all(24),
              child: GuestAccountCard(),
            ),
          ),
        ),
      );

      _expectNoException(tester);
      _expectLaidOut(tester, size, [
        'Guest account',
        'Create an account to keep',
        'Create account',
      ], checkVertical: false);
    });

    testWidgets('auth buttons fit ($tag)', (tester) async {
      final router = GoRouter(
        routes: [GoRoute(path: '/', builder: (_, _) => const AuthScreen())],
      );
      addTearDown(router.dispose);
      AuthNotifier.platformOverride = AuthPlatform.ios;
      addTearDown(() => AuthNotifier.platformOverride = null);
      await _pump(
        tester,
        size,
        buildTestWidgetWithRouter(
          router,
          overrides: [
            authNotifierProvider.overrideWith(_FakeAuth.new),
            isGuestProvider.overrideWithValue(true),
          ],
        ),
      );

      _expectNoException(tester);
      final apple = find.byType(SignInWithAppleButton);
      await tester.ensureVisible(apple);
      await tester.pump();
      final label = find.text(AppStrings.signInWithApple);
      expect(label, findsOneWidget);
      final buttonRect = tester.getRect(apple);
      final labelRect = tester.getRect(label);
      expect(labelRect.left, greaterThanOrEqualTo(buttonRect.left));
      expect(labelRect.right, lessThanOrEqualTo(buttonRect.right));
      expect(
        labelRect.height,
        lessThanOrEqualTo(buttonRect.height),
        reason: 'the label must stay on one line inside the button',
      );
      expect(buttonRect.right, lessThanOrEqualTo(size.width + 0.5));
    });
  }
}
