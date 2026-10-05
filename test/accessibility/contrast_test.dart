import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icos/core/constants/app_colors.dart';
import 'package:icos/core/services/auth_session_provider.dart';
import 'package:icos/core/services/connectivity_service.dart';
import 'package:icos/core/services/edge_function_client.dart';
import 'package:icos/core/services/session_service.dart';
import 'package:icos/core/services/storage_service.dart';
import 'package:icos/core/services/sync_service.dart';
import 'package:icos/core/theme/app_theme.dart';
import 'package:icos/core/utils/date_utils.dart';
import 'package:icos/features/profile/presentation/widgets/theme_mode_dropdown.dart';
import 'package:icos/features/puzzle/data/puzzle_repository.dart';
import 'package:icos/features/puzzle/data/submission_result.dart';
import 'package:icos/features/puzzle/domain/models/puzzle.dart';
import 'package:icos/features/puzzle/presentation/puzzle_screen.dart';
import 'package:icos/features/puzzle/presentation/widgets/celebration_overlay.dart';
import 'package:icos/features/puzzle/presentation/widgets/offline_puzzle_notice.dart';
import 'package:icos/features/puzzle/providers/daily_puzzle_provider.dart';
import 'package:icos/shared/widgets/offline_banner.dart';

import '../helpers/contrast.dart';
import '../helpers/storage_test_helpers.dart';
import '../helpers/test_helpers.dart';

class _Online extends ConnectivityNotifier {
  @override
  bool build() => true;
}

class _Offline extends ConnectivityNotifier {
  @override
  bool build() => false;
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

const _themes = <String, bool>{'light': false, 'dark': true};

ThemeData _theme(bool dark) => dark ? AppTheme.darkTheme : AppTheme.lightTheme;

void main() {
  setUpTestEnvironment();

  late Directory dir;
  setUp(() async => dir = await initTestStorage());
  tearDown(() async => dir.delete(recursive: true));

  final today = AppDateUtils.todayUtc();

  List<Override> puzzleOverrides(Future<Puzzle> Function() load) => [
    puzzleForDateProvider(today).overrideWith((ref) => load()),
    puzzleRepositoryProvider.overrideWithValue(_NoAttempts()),
    authSessionProvider.overrideWithValue(const FakeAuthSessionInfo()),
    connectivityNotifierProvider.overrideWith(_Online.new),
    edgeInvokerProvider.overrideWithValue(
      (fn, body) async => const EdgeResponse(200, {'nonce': 'n'}),
    ),
    sessionEnsurerProvider.overrideWithValue(
      SessionEnsurer(gateway: _SignedIn()),
    ),
  ];

  Future<void> pumpPuzzle(
    WidgetTester tester, {
    required bool dark,
    required String date,
    required Future<Puzzle> Function() load,
  }) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: puzzleOverrides(load),
        child: MaterialApp(
          theme: _theme(dark),
          home: PuzzleScreen.forDate(date),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  for (final entry in _themes.entries) {
    final dark = entry.value;
    group('contrast (${entry.key} theme)', () {
      testWidgets('"not available yet" title and body', (tester) async {
        await pumpPuzzle(
          tester,
          dark: dark,
          date: AppDateUtils.tomorrowUtc(),
          load: () async => smallTestPuzzle,
        );
        final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
        final bg = scaffold.backgroundColor!;
        for (final label in [
          'This puzzle is not available yet',
          "Each day's puzzle unlocks at midnight UTC.",
        ]) {
          expect(
            textContrast(tester, find.text(label), fallbackBackground: bg),
            greaterThanOrEqualTo(4.5),
            reason: label,
          );
        }
      });

      testWidgets('theme dropdown menu options', (tester) async {
        await tester.pumpWidget(
          buildTestWidgetInScaffold(
            const Align(
              alignment: Alignment.topRight,
              child: ThemeModeDropdown(),
            ),
            theme: _theme(dark),
          ),
        );
        await tester.tap(find.byType(DropdownButton<ThemeMode>));
        await tester.pumpAndSettle();

        final menuBg =
            tester
                .widget<DropdownButton<ThemeMode>>(
                  find.byType(DropdownButton<ThemeMode>),
                )
                .dropdownColor ??
            Theme.of(
              tester.element(find.byType(DropdownButton<ThemeMode>)),
            ).canvasColor;
        for (final label in ['System', 'Dark', 'Light']) {
          final option = find.text(label).last;
          expect(
            contrastRatio(resolvedTextColor(tester, option), menuBg),
            greaterThanOrEqualTo(4.5),
            reason: 'menu option $label',
          );
        }
      });

      testWidgets('offline banner text', (tester) async {
        await tester.pumpWidget(
          buildTestWidgetInScaffold(
            const Column(children: [OfflineBanner()]),
            theme: _theme(dark),
            overrides: [
              connectivityNotifierProvider.overrideWith(_Offline.new),
              syncQueueLengthProvider.overrideWith((ref) => Stream.value(0)),
            ],
          ),
        );
        await tester.pump();
        final scaffoldBg = _theme(dark).scaffoldBackgroundColor;
        expect(
          textContrast(
            tester,
            find.textContaining("You're offline"),
            fallbackBackground: scaffoldBg,
          ),
          greaterThanOrEqualTo(4.5),
        );
      });
    });
  }

  group('contrast sweep: always-dark puzzle surfaces in light theme', () {
    testWidgets('HUD, controls and practice notice', (tester) async {
      await pumpPuzzle(
        tester,
        dark: false,
        date: today,
        load: () async => smallTestPuzzle.copyWith(
          puzzleDate: today,
          origin: PuzzleOrigin.bundled,
        ),
      );
      expect(find.byType(OfflinePuzzleNotice), findsOneWidget);
      expect(find.byKey(const Key('puzzle_hud')), findsOneWidget);
      expect(
        contrastFailures(tester, fallbackBackground: AppColors.deepBlack),
        isEmpty,
      );
    });

    testWidgets('loading state', (tester) async {
      final never = Completer<Puzzle>();
      await pumpPuzzle(
        tester,
        dark: false,
        date: today,
        load: () => never.future,
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        contrastFailures(tester, fallbackBackground: AppColors.deepBlack),
        isEmpty,
      );
    });

    testWidgets('error state', (tester) async {
      await pumpPuzzle(
        tester,
        dark: false,
        date: today,
        load: () async => throw StateError('boom'),
      );
      expect(find.text('Could not load puzzle'), findsOneWidget);
      expect(
        contrastFailures(tester, fallbackBackground: AppColors.deepBlack),
        isEmpty,
      );
    });

    testWidgets('result card', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        buildTestWidgetInScaffold(
          const Stack(
            children: [
              CelebrationOverlay(
                timeSeconds: 42,
                hintsUsed: 1,
                parTimeSeconds: 60,
                gridSize: 5,
                difficulty: 'easy',
              ),
            ],
          ),
          theme: AppTheme.lightTheme,
        ),
      );
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Crushed It!'), findsOneWidget);
      expect(
        contrastFailures(tester, fallbackBackground: AppColors.deepBlack),
        isEmpty,
      );
    });
  });
}
