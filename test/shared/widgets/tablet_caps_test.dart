import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:icos/core/services/auth_session_provider.dart';
import 'package:icos/core/services/connectivity_service.dart';
import 'package:icos/core/services/edge_function_client.dart';
import 'package:icos/core/services/session_service.dart';
import 'package:icos/core/services/storage_service.dart';
import 'package:icos/core/utils/date_utils.dart';
import 'package:icos/features/puzzle/data/puzzle_repository.dart';
import 'package:icos/features/puzzle/data/puzzle_source.dart';
import 'package:icos/features/puzzle/data/submission_result.dart';
import 'package:icos/features/puzzle/presentation/puzzle_screen.dart';
import 'package:icos/features/puzzle/presentation/widgets/game_controls.dart';
import 'package:icos/features/puzzle/presentation/widgets/puzzle_grid.dart';
import 'package:icos/features/puzzle/providers/daily_puzzle_provider.dart';
import 'package:icos/shared/widgets/animated_background.dart';
import 'package:icos/shared/widgets/app_shell.dart';
import 'package:icos/shared/widgets/content_width.dart';

import '../../helpers/storage_test_helpers.dart';
import '../../helpers/test_helpers.dart';

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
  tearDown(() async => dir.delete(recursive: true));

  Future<void> useScreen(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  const portrait = Size(834, 1194);
  const landscape = Size(1194, 834);
  const phone = Size(393, 852);

  Finder gridSquare() => find
      .descendant(
        of: find.byType(PuzzleGrid),
        matching: find.byWidgetPredicate(
          (w) => w is SizedBox && w.width != null && w.width == w.height,
        ),
      )
      .first;

  for (final size in [portrait, landscape]) {
    final tag = '${size.width.toInt()}x${size.height.toInt()}';

    testWidgets('ContentWidth caps a body at 600dp, centred ($tag)', (
      tester,
    ) async {
      await useScreen(tester, size);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ContentWidth(child: Container(key: const Key('c'))),
          ),
        ),
      );
      final rect = tester.getRect(find.byKey(const Key('c')));
      expect(rect.width, 600);
      expect(rect.center.dx, size.width / 2);
      expect(rect.height, size.height, reason: 'height stays tight');
    });

    testWidgets('AppShell: body capped, nav bar and background full ($tag)', (
      tester,
    ) async {
      await useScreen(tester, size);
      final router = GoRouter(
        routes: [
          ShellRoute(
            builder: (context, state, child) => AppShell(child: child),
            routes: [
              GoRoute(
                path: '/',
                builder: (_, _) => Container(key: const Key('tab')),
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        buildTestWidgetWithRouter(
          router,
          overrides: [connectivityNotifierProvider.overrideWith(_Online.new)],
        ),
      );
      await tester.pump();

      final body = tester.getRect(find.byKey(const Key('tab')));
      expect(body.width, lessThanOrEqualTo(600));
      expect(body.center.dx, size.width / 2);
      expect(
        tester.getSize(find.byType(BottomNavigationBar)).width,
        size.width,
      );
      expect(tester.getSize(find.byType(AnimatedBackground)).width, size.width);
    });

    testWidgets('puzzle: background full, grid <= 500, HUD aligned ($tag)', (
      tester,
    ) async {
      await useScreen(tester, size);
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
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(tester.getSize(find.byType(AnimatedBackground)).width, size.width);
      final grid = tester.getRect(gridSquare());
      expect(grid.width, lessThanOrEqualTo(500));
      expect(grid.center.dx, size.width / 2);
      final controls = tester.getRect(find.byType(GameControls));
      final hud = tester.getRect(find.byKey(const Key('puzzle_hud')));
      expect(controls.width, lessThanOrEqualTo(548));
      // HUD and controls share the grid's column: never wider than 500 and
      // centred with it (the grid is narrower only when height-limited).
      expect(hud.width, lessThanOrEqualTo(500.5));
      expect(hud.center.dx, closeTo(grid.center.dx, 0.5));
      expect(grid.width, lessThanOrEqualTo(hud.width + 0.5));
      if (size.width < size.height) {
        expect(hud.left, closeTo(grid.left, 0.5));
      }
      // The home button's leading edge lines up with the HUD / grid column.
      final home = tester.getRect(
        find
            .ancestor(
              of: find.byIcon(Icons.home_rounded),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(home.size, const Size(44, 44));
      expect(home.left, closeTo(hud.left, 0.5));
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('phones are unaffected by ContentWidth', (tester) async {
    await useScreen(tester, phone);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ContentWidth(child: Container(key: const Key('c'))),
        ),
      ),
    );
    expect(tester.getSize(find.byKey(const Key('c'))).width, phone.width);
  });

  testWidgets('the puzzle grid still fills a phone', (tester) async {
    await useScreen(tester, phone);
    await tester.pumpWidget(
      buildTestWidgetInScaffold(
        PuzzleGrid(
          gameState: createPlayingGameState(),
          onCellTap: (_, _) {},
          onCellDrag: (_, _) {},
        ),
      ),
    );
    expect(tester.getSize(gridSquare()).width, phone.width - 48);
  });
}
