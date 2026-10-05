import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:icos/core/services/auth_session_provider.dart';
import 'package:icos/core/services/connectivity_service.dart';
import 'package:icos/core/services/edge_function_client.dart';
import 'package:icos/core/services/session_service.dart';
import 'package:icos/core/utils/date_utils.dart';
import 'package:icos/features/puzzle/data/puzzle_repository.dart';
import 'package:icos/features/puzzle/data/puzzle_source.dart';
import 'package:icos/features/puzzle/data/submission_result.dart';
import 'package:icos/features/puzzle/presentation/puzzle_screen.dart';
import 'package:icos/features/puzzle/presentation/widgets/puzzle_grid.dart';
import 'package:icos/features/puzzle/providers/daily_puzzle_provider.dart';

import '../../../helpers/storage_test_helpers.dart';
import '../../../helpers/test_helpers.dart';

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

void main() {
  setUpTestEnvironment();

  late Directory dir;
  setUp(() async => dir = await initTestStorage());
  tearDown(() async {
    AppDateUtils.clock = DateTime.now;
    await dir.delete(recursive: true);
  });

  Future<void> open(WidgetTester tester, String date) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final puzzle = smallTestPuzzle.copyWith(puzzleDate: date);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => PuzzleScreen(source: PuzzleSource.daily(date)),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      buildTestWidgetWithRouter(
        router,
        overrides: [
          puzzleForDateProvider(date).overrideWith((ref) async => puzzle),
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
    await tester.pump();
  }

  testWidgets('left open across midnight UTC, "not available yet" becomes the '
      'playable puzzle', (tester) async {
    var now = DateTime.utc(2026, 10, 5, 23, 59, 50);
    AppDateUtils.clock = () => now;

    await open(tester, '2026-10-06');
    expect(find.text('This puzzle is not available yet'), findsOneWidget);

    // Ten seconds to midnight, plus a second of slack: nothing before that.
    await tester.pump(const Duration(seconds: 10));
    expect(find.text('This puzzle is not available yet'), findsOneWidget);

    now = DateTime.utc(2026, 10, 6, 0, 0, 1);
    await tester.pump(const Duration(seconds: 1));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('This puzzle is not available yet'), findsNothing);
    expect(find.byType(PuzzleGrid), findsOneWidget);

    // Leaving the screen cancels whatever is still scheduled (the harness
    // fails the test on a pending timer).
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('also re-checks the date when the app resumes (a Dart timer '
      'does not run while asleep)', (tester) async {
    var now = DateTime.utc(2026, 10, 5, 22);
    AppDateUtils.clock = () => now;
    await open(tester, '2026-10-06');
    expect(find.text('This puzzle is not available yet'), findsOneWidget);

    // The device slept through midnight: no timer time elapsed in the app.
    now = DateTime.utc(2026, 10, 6, 7);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('This puzzle is not available yet'), findsNothing);
    expect(find.byType(PuzzleGrid), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the timer is cancelled when the screen goes away first', (
    tester,
  ) async {
    AppDateUtils.clock = () => DateTime.utc(2026, 10, 5, 12);
    await open(tester, '2026-10-06');
    expect(find.text('This puzzle is not available yet'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    // A timer still pending here (twelve hours out) would fail the test.
  });

  testWidgets('a date two days ahead keeps waiting, one timer at a time', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 10, 5, 23, 59, 50);
    AppDateUtils.clock = () => now;
    await open(tester, '2026-10-07');

    now = DateTime.utc(2026, 10, 6, 0, 0, 1);
    await tester.pump(const Duration(seconds: 11));
    expect(find.text('This puzzle is not available yet'), findsOneWidget);

    now = DateTime.utc(2026, 10, 7, 0, 0, 1);
    await tester.pump(const Duration(hours: 24));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('This puzzle is not available yet'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  test('untilNextUtcMidnight is the time to 00:00 UTC', () {
    AppDateUtils.clock = () => DateTime.utc(2026, 10, 5, 23, 59, 50);
    addTearDown(() => AppDateUtils.clock = DateTime.now);
    expect(AppDateUtils.untilNextUtcMidnight(), const Duration(seconds: 10));
    AppDateUtils.clock = () => DateTime.utc(2026, 10, 6);
    expect(AppDateUtils.untilNextUtcMidnight(), const Duration(days: 1));
  });
}
