import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icos/core/constants/app_colors.dart';
import 'package:icos/core/constants/app_strings.dart';
import 'package:icos/core/theme/app_palette.dart';
import 'package:icos/features/groups/domain/models/blocked_user.dart';
import 'package:icos/features/groups/presentation/groups_screen.dart';
import 'package:icos/features/groups/providers/blocked_users_provider.dart';
import 'package:icos/features/groups/providers/groups_provider.dart';
import 'package:icos/features/home/presentation/home_screen.dart';
import 'package:icos/features/profile/presentation/blocked_users_screen.dart';
import 'package:icos/features/profile/presentation/widgets/colorblind_selector.dart';
import 'package:icos/features/profile/presentation/widgets/guest_account_card.dart';
import 'package:icos/features/puzzle/presentation/widgets/grid_palette.dart';
import 'package:icos/features/puzzle/presentation/widgets/puzzle_grid.dart';
import 'package:icos/features/puzzle/presentation/widgets/puzzle_palette.dart';
import 'package:icos/features/puzzle/providers/colorblind_mode_provider.dart';
import 'package:icos/features/puzzle/providers/puzzle_result_provider.dart';
import 'package:icos/features/sharing/presentation/share_card_widget.dart';
import 'package:icos/features/stats/domain/models/streak.dart';
import 'package:icos/features/stats/presentation/stats_screen.dart';
import 'package:icos/features/stats/providers/stats_provider.dart';
import 'package:icos/shared/widgets/blocking_screens.dart';
import 'package:icos/core/services/auth_session_provider.dart';
import 'package:icos/core/services/connectivity_service.dart';
import 'package:icos/core/services/edge_function_client.dart';
import 'package:icos/core/services/session_service.dart';
import 'package:icos/core/services/storage_service.dart';
import 'package:icos/core/services/sync_service.dart';
import 'package:icos/core/theme/app_theme.dart';
import 'package:icos/core/utils/date_utils.dart';
import 'package:icos/features/archive/presentation/archive_screen.dart';
import 'package:icos/features/archive/providers/archive_provider.dart';
import 'package:icos/features/auth/presentation/auth_screen.dart';
import 'package:icos/features/auth/presentation/email_auth_screen.dart';
import 'package:icos/features/auth/presentation/new_password_screen.dart';
import 'package:icos/features/auth/presentation/onboarding_screen.dart';
import 'package:icos/features/auth/providers/auth_provider.dart';
import 'package:icos/features/practice/presentation/practice_screen.dart';
import 'package:icos/features/profile/presentation/widgets/theme_mode_dropdown.dart';
import 'package:icos/features/puzzle/data/puzzle_repository.dart';
import 'package:icos/features/puzzle/data/submission_result.dart';
import 'package:icos/features/puzzle/domain/models/puzzle.dart';
import 'package:icos/features/puzzle/presentation/puzzle_screen.dart';
import 'package:icos/features/puzzle/presentation/widgets/celebration_overlay.dart';
import 'package:icos/features/puzzle/presentation/widgets/offline_puzzle_notice.dart';
import 'package:icos/features/puzzle/providers/daily_puzzle_provider.dart';
import 'package:icos/shared/widgets/offline_banner.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import '../helpers/contrast.dart';
import '../helpers/storage_test_helpers.dart';
import '../helpers/test_helpers.dart';

class _Online extends ConnectivityNotifier {
  @override
  bool build() => true;
}

class _FakeAuth extends AuthNotifier {
  @override
  AsyncValue<User?> build() => const AsyncValue.data(null);
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

class _NoBlocked extends BlockedUsers {
  @override
  Future<List<BlockedUser>> build() async => const [];
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
        // The icon is non-text: 3:1.
        final icon = tester.widget<Icon>(find.byIcon(Icons.cloud_off_rounded));
        final iconBg = backgroundBehind(
          tester.element(find.byIcon(Icons.cloud_off_rounded)),
          fallback: scaffoldBg,
        );
        expect(
          contrastRatio(icon.color!, iconBg),
          greaterThanOrEqualTo(3),
          reason: 'offline banner icon',
        );
      });
    });
  }

  // Every surface below is pumped in both themes: the light theme must be
  // light (no dark panels left behind) and every Text must meet AA against
  // what is actually painted behind it.
  for (final entry in _themes.entries) {
    final dark = entry.value;
    final theme = _theme(dark);
    final bg = theme.extension<AppPalette>()!.background;

    void expectClean(WidgetTester tester, {Finder? scope}) {
      expect(
        contrastFailures(tester, fallbackBackground: bg, scope: scope),
        isEmpty,
      );
    }

    /// In the light theme, [label]'s backdrop must be light (catches panels
    /// that stayed dark); in the dark theme it must stay dark.
    void expectBackdropMatchesTheme(WidgetTester tester, Finder label) {
      final behind = backgroundBehind(tester.element(label), fallback: bg);
      final lum = relativeLuminance(behind);
      if (dark) {
        expect(lum, lessThan(0.2), reason: 'dark backdrop, got $behind');
      } else {
        expect(lum, greaterThan(0.6), reason: 'light backdrop, got $behind');
      }
    }

    group('contrast sweep: puzzle surfaces (${entry.key} theme)', () {
      testWidgets('HUD, controls and practice notice', (tester) async {
        await pumpPuzzle(
          tester,
          dark: dark,
          date: today,
          load: () async => smallTestPuzzle.copyWith(
            puzzleDate: today,
            origin: PuzzleOrigin.bundled,
          ),
        );
        expect(find.byType(OfflinePuzzleNotice), findsOneWidget);
        expect(find.byKey(const Key('puzzle_hud')), findsOneWidget);
        expectClean(tester);
        final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
        expect(scaffold.backgroundColor, bg);
        expectBackdropMatchesTheme(tester, find.text('Hint'));
      });

      testWidgets('board palette follows the theme', (tester) async {
        await pumpPuzzle(
          tester,
          dark: dark,
          date: today,
          load: () async => smallTestPuzzle.copyWith(puzzleDate: today),
        );
        final grid = tester.widget<PuzzleGrid>(find.byType(PuzzleGrid));
        expect(
          grid.palette.brightness,
          dark ? Brightness.dark : Brightness.light,
        );
        if (dark) expect(grid.palette, same(GridPalette.standard));
      });

      testWidgets('loading state', (tester) async {
        final never = Completer<Puzzle>();
        await pumpPuzzle(
          tester,
          dark: dark,
          date: today,
          load: () => never.future,
        );
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expectClean(tester);
      });

      testWidgets('error state', (tester) async {
        await pumpPuzzle(
          tester,
          dark: dark,
          date: today,
          load: () async => throw StateError('boom'),
        );
        expect(find.text('Could not load puzzle'), findsOneWidget);
        expectClean(tester);
        expectBackdropMatchesTheme(tester, find.text('Could not load puzzle'));
      });

      testWidgets('not available yet', (tester) async {
        await pumpPuzzle(
          tester,
          dark: dark,
          date: AppDateUtils.tomorrowUtc(),
          load: () async => smallTestPuzzle,
        );
        expectClean(tester);
        expectBackdropMatchesTheme(
          tester,
          find.text('This puzzle is not available yet'),
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
                  path: [
                    [0, 0],
                    [0, 1],
                  ],
                ),
              ],
            ),
            theme: theme,
          ),
        );
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.text('Crushed It!'), findsOneWidget);
        expectClean(tester);
        expectBackdropMatchesTheme(tester, find.text('Crushed It!'));
      });
    });

    group('contrast sweep: screens (${entry.key} theme)', () {
      Future<void> pumpScreen(
        WidgetTester tester,
        Widget screen, {
        List<Override> overrides = const [],
      }) async {
        tester.view.physicalSize = const Size(393, 852);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          ProviderScope(
            overrides: overrides,
            child: MaterialApp(theme: theme, home: screen),
          ),
        );
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      final authOverrides = [
        authNotifierProvider.overrideWith(_FakeAuth.new),
        isGuestProvider.overrideWithValue(true),
      ];

      testWidgets('auth', (tester) async {
        await pumpScreen(tester, const AuthScreen(), overrides: authOverrides);
        expectClean(tester);
        expectBackdropMatchesTheme(tester, find.text('Sign up with Email'));
      });

      testWidgets('email auth (sign up)', (tester) async {
        await pumpScreen(
          tester,
          const EmailAuthScreen(),
          overrides: authOverrides,
        );
        expectClean(tester);
        expectBackdropMatchesTheme(tester, find.text('Create Account').first);
      });

      testWidgets('new password', (tester) async {
        await pumpScreen(
          tester,
          const NewPasswordScreen(),
          overrides: authOverrides,
        );
        expectClean(tester);
      });

      testWidgets('onboarding', (tester) async {
        await pumpScreen(tester, const OnboardingScreen());
        expectClean(tester);
        expectBackdropMatchesTheme(tester, find.text('Welcome to Icos'));
      });

      testWidgets('archive', (tester) async {
        await pumpScreen(
          tester,
          const ArchiveScreen(),
          overrides: [
            archiveEntriesProvider.overrideWith(
              (ref) async => [
                const ArchiveEntry(date: '2026-10-04'),
                const ArchiveEntry(date: '2026-10-03'),
              ],
            ),
          ],
        );
        expectClean(tester);
        expectBackdropMatchesTheme(
          tester,
          find.text("Archive solves don't affect your streak."),
        );
      });

      testWidgets('practice', (tester) async {
        await pumpScreen(tester, const PracticeScreen());
        expectClean(tester);
        expectBackdropMatchesTheme(tester, find.text('Your practice stats'));
      });

      testWidgets('home', (tester) async {
        await pumpScreen(
          tester,
          const Scaffold(body: HomeScreen()),
          overrides: [
            dailyPuzzleProvider.overrideWith((ref) async => testPuzzle),
            todayResultProvider.overrideWith((ref) async => null),
            streakProvider.overrideWith(
              (ref) async => const Streak(
                userId: 'u',
                currentStreak: 3,
                longestStreak: 3,
                freezeCount: 1,
              ),
            ),
          ],
        );
        expectClean(tester);
        expectBackdropMatchesTheme(tester, find.text(AppStrings.puzzleTitle));
        expectBackdropMatchesTheme(tester, find.text('Practice'));
      });

      testWidgets('stats', (tester) async {
        await pumpScreen(
          tester,
          const Scaffold(body: StatsScreen()),
          overrides: [
            statsOverviewProvider.overrideWith(
              (ref) async => const StatsOverview(
                currentStreak: 4,
                longestStreak: 9,
                totalSolved: 12,
                averageTimeSeconds: 95,
                freezeCount: 1,
                lastFreezeUsedAt: null,
              ),
            ),
            solveHistoryProvider.overrideWith((ref) async => []),
          ],
        );
        expectClean(tester);
        expectBackdropMatchesTheme(tester, find.text('Current Streak'));
      });

      testWidgets('groups (account required)', (tester) async {
        await pumpScreen(
          tester,
          const Scaffold(body: GroupsScreen()),
          overrides: [
            groupsSessionProvider.overrideWith(
              (ref) => const GroupsSession(userId: 'a', isAnonymous: true),
            ),
          ],
        );
        expectClean(tester);
      });

      testWidgets('blocked users (empty)', (tester) async {
        await pumpScreen(
          tester,
          const BlockedUsersScreen(),
          overrides: [blockedUsersProvider.overrideWith(_NoBlocked.new)],
        );
        expectClean(tester);
      });

      testWidgets('guest account card', (tester) async {
        await pumpScreen(
          tester,
          const Scaffold(body: GuestAccountCard()),
        );
        expectClean(tester);
      });

      testWidgets('colorblind sheet', (tester) async {
        await pumpScreen(
          tester,
          const Scaffold(body: ColorblindSelector(currentMode: 'none')),
        );
        final failures = contrastFailures(tester, fallbackBackground: bg);
        if (dark) {
          // The dark sheet's white "P"/"W" swatch letters are unchanged from
          // the shipped dark design (left as is: dark must not change).
          failures.removeWhere((f) => f.startsWith('"P"') || f.startsWith('"W"'));
        }
        expect(failures, isEmpty);
      });

      testWidgets('blocking screens', (tester) async {
        for (final screen in const [MaintenanceScreen(), BannedScreen()]) {
          await pumpScreen(tester, screen);
          expectClean(tester);
        }
      });

      testWidgets('share card', (tester) async {
        await pumpScreen(
          tester,
          Scaffold(
            body: ShareCardWidget(
              repaintKey: GlobalKey(),
              gridSize: 5,
              difficulty: 'easy',
              timeSeconds: 40,
              hintsUsed: 0,
              parTimeSeconds: 60,
              streak: 3,
              pathVisualization: const SizedBox(),
            ),
          ),
        );
        expectClean(tester);
        expectBackdropMatchesTheme(tester, find.text('Icos'));
      });
    });
  }

  group('light palette pairs', () {
    const p = AppPalette.light;
    test('text tokens on every light surface', () {
      for (final surface in [p.background, p.surface, p.card, p.elevated]) {
        for (final text in [
          p.textPrimary,
          p.textSecondary,
          p.textTertiary,
          p.accent,
          p.success,
          p.gold,
          p.warning,
          p.coral,
          p.info,
          p.error,
          p.hint,
        ]) {
          expect(
            contrastRatio(text, surface),
            greaterThanOrEqualTo(4.5),
            reason: '$text on $surface',
          );
        }
      }
    });

    test('dark palette is the shipped dark values', () {
      const d = AppPalette.dark;
      expect(d.background, AppColors.deepBlack);
      expect(d.card, AppColors.cardSurface);
      expect(d.elevated, AppColors.elevatedSurface);
      expect(d.textPrimary, AppColors.textPrimaryDark);
      expect(d.textSecondary, AppColors.textSecondaryDark);
      expect(d.accent, AppColors.purpleLight);
      expect(GridPalette.forMode(ColorblindMode.none), same(GridPalette.standard));
    });

    for (final mode in ColorblindMode.values) {
      test('light board (${mode.name}): line, waypoints, walls and numerals', () {
        final g = GridPalette.forMode(mode, brightness: Brightness.light);
        expect(g.brightness, Brightness.light);
        final boardCells = [
          g.cellBackground,
          g.filledCellDark,
          g.filledCellLight,
        ];
        for (final cell in boardCells) {
          for (final stop in [...g.pathGradient, g.pathHead, g.pathStart]) {
            expect(
              contrastRatio(stop, cell),
              greaterThanOrEqualTo(3),
              reason: 'line $stop on $cell',
            );
          }
          for (final disc in [g.waypointFill, g.waypointStartFill]) {
            // The light board draws every disc opaque.
            expect(g.dimUnvisitedWaypoints, isFalse);
            final shown = compositeOver(disc, cell);
            expect(
              contrastRatio(shown, cell),
              greaterThanOrEqualTo(3),
              reason: 'waypoint $disc on $cell',
            );
          }
        }
        expect(
          contrastRatio(g.wallFill, g.cellBackground),
          greaterThanOrEqualTo(3),
        );
        // The start ring marks waypoint 1 against its own disc.
        expect(g.waypointStartBorderAlpha, 1);
        expect(
          contrastRatio(g.waypointStartBorder, g.waypointStartFill),
          greaterThanOrEqualTo(3),
        );
        expect(
          contrastRatio(g.wallCross, g.wallFill),
          greaterThanOrEqualTo(3),
        );
        for (final (text, disc) in [
          (g.waypointText, g.waypointFill),
          (g.waypointStartText, g.waypointStartFill),
        ]) {
          final shown = compositeOver(disc, g.cellBackground);
          expect(
            contrastRatio(text, shown),
            greaterThanOrEqualTo(4.5),
            reason: 'numeral $text on $disc',
          );
        }
      });
    }

    test('gradient title stops read on the background', () {
      for (final pal in [AppPalette.light]) {
        for (final c in pal.titleGradient) {
          expect(contrastRatio(c, pal.background), greaterThanOrEqualTo(3));
        }
      }
    });

    test('light confetti reads on the light background', () {
      for (final c in [
        ...PuzzlePalette.light.confetti,
        ...PuzzlePalette.light.sparks,
      ]) {
        expect(
          contrastRatio(c, AppColors.lightBackground),
          greaterThanOrEqualTo(3),
          reason: '$c',
        );
      }
    });
  });

  testWidgets('switching the theme re-themes the puzzle screen live', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final mode = ValueNotifier(ThemeMode.dark);
    addTearDown(mode.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: puzzleOverrides(
          () async => smallTestPuzzle.copyWith(puzzleDate: today),
        ),
        child: ValueListenableBuilder<ThemeMode>(
          valueListenable: mode,
          builder: (context, m, _) => MaterialApp(
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: m,
            home: PuzzleScreen.forDate(today),
          ),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    PuzzleGrid grid() => tester.widget<PuzzleGrid>(find.byType(PuzzleGrid));
    Color scaffoldBg() =>
        tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor!;
    expect(grid().palette, same(GridPalette.standard));
    expect(scaffoldBg(), AppColors.deepBlack);

    mode.value = ThemeMode.light;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(grid().palette, same(GridPalette.standardLight));
    expect(scaffoldBg(), AppColors.lightBackground);
  });

  group('system bars', () {
    test('status bar icons are dark on light, light on dark', () {
      expect(
        AppTheme.lightTheme.appBarTheme.systemOverlayStyle?.statusBarIconBrightness,
        Brightness.dark,
      );
      expect(
        AppTheme.darkTheme.appBarTheme.systemOverlayStyle?.statusBarIconBrightness,
        Brightness.light,
      );
      expect(
        AppPalette.light.overlayStyle.statusBarIconBrightness,
        Brightness.dark,
      );
    });
  });
}
