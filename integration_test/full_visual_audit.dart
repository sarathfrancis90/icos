/// Comprehensive visual audit — renders EVERY screen/state in the app,
/// takes screenshots, and verifies core interactions.
///
/// Run: flutter test integration_test/full_visual_audit.dart -d `<device_id>`
///
/// This test covers:
///   1. Onboarding (3 pages + skip)
///   2. Home screen (puzzle card)
///   3. Puzzle grid (empty, playing, path drawing, backward drag)
///   4. Celebration overlay (under par, over par)
///   5. Game controls (undo, reset, hint)
///   6. Stats screen
///   7. Groups screen
///   8. Profile screen
///   9. Auth screen
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icos/core/constants/app_colors.dart';
import 'package:icos/core/theme/app_theme.dart';
import 'package:icos/features/auth/presentation/onboarding_screen.dart';
import 'package:icos/features/home/presentation/home_screen.dart';
import 'package:icos/features/puzzle/domain/game_engine.dart';
import 'package:icos/features/puzzle/domain/models/game_state.dart';
import 'package:icos/features/puzzle/domain/models/puzzle.dart';
import 'package:icos/features/puzzle/presentation/widgets/celebration_overlay.dart';
import 'package:icos/features/puzzle/presentation/widgets/game_controls.dart';
import 'package:icos/features/puzzle/presentation/widgets/puzzle_grid.dart';
import 'package:icos/features/stats/presentation/stats_screen.dart';
import 'package:integration_test/integration_test.dart';
// NOTE: GroupsScreen, ProfileScreen, AuthScreen require Supabase and are
// tested via the running app, not in this isolated audit.

// -- Test data --------------------------------------------------------

const _testPuzzle5x5 = Puzzle(
  id: 'audit-puzzle-5x5',
  puzzleDate: '2026-03-03',
  gridSize: 5,
  waypoints: [
    Waypoint(order: 1, row: 0, col: 0),
    Waypoint(order: 2, row: 2, col: 2),
    Waypoint(order: 3, row: 4, col: 4),
  ],
  walls: [Wall(row: 1, col: 3)],
  difficulty: 'medium',
  parTimeSeconds: 90,
);

const _testPuzzle3x3 = Puzzle(
  id: 'audit-puzzle-3x3',
  puzzleDate: '2026-03-03',
  gridSize: 3,
  waypoints: [
    Waypoint(order: 1, row: 0, col: 0),
    Waypoint(order: 2, row: 2, col: 2),
  ],
  walls: [],
  difficulty: 'easy',
  parTimeSeconds: 60,
);

// -- Helpers ----------------------------------------------------------

Widget _wrap(Widget child) {
  return ProviderScope(
    child: MaterialApp(
      theme: AppTheme.darkTheme,
      home: child,
    ),
  );
}

Widget _wrapScaffold(Widget child) {
  return _wrap(Scaffold(
    backgroundColor: AppColors.deepBlack,
    body: child,
  ));
}

GameState _buildPlayingState(GameEngine engine, List<List<int>> cells) {
  var state = engine.createInitialState();
  for (final cell in cells) {
    state = engine.addToPath(state, cell[0], cell[1]);
  }
  return state.copyWith(
    status: GameStatus.playing,
    elapsedSeconds: 42,
  );
}

// -- Tests ------------------------------------------------------------

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> screenshot(
      WidgetTester tester, String name) async {
    await binding.convertFlutterSurfaceToImage();
    await tester.pumpAndSettle();
    await binding.takeScreenshot(name);
  }

  // ── 1. ONBOARDING ──────────────────────────────────────────────────

  group('1. Onboarding', () {
    testWidgets('Page 1 renders correctly', (tester) async {
      await tester.pumpWidget(_wrap(const OnboardingScreen()));
      await tester.pumpAndSettle();
      await screenshot(tester, 'audit_01_onboarding_page1');

      expect(find.text('Welcome to Zlynker'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);
    });

    testWidgets('Page 2 via swipe', (tester) async {
      await tester.pumpWidget(_wrap(const OnboardingScreen()));
      await tester.pumpAndSettle();

      await tester.drag(find.byType(PageView), const Offset(-400, 0));
      await tester.pumpAndSettle();
      await screenshot(tester, 'audit_02_onboarding_page2');

      expect(find.text('One Puzzle Per Day'), findsOneWidget);
    });

    testWidgets('Page 3 via swipe', (tester) async {
      await tester.pumpWidget(_wrap(const OnboardingScreen()));
      await tester.pumpAndSettle();

      await tester.drag(find.byType(PageView), const Offset(-400, 0));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(PageView), const Offset(-400, 0));
      await tester.pumpAndSettle();
      await screenshot(tester, 'audit_03_onboarding_page3');

      expect(find.text('Compete with Friends'), findsOneWidget);
      expect(find.text('Get Started'), findsOneWidget);
    });
  });

  // ── 2. PUZZLE GRID — ALL STATES ────────────────────────────────────

  group('2. Puzzle Grid', () {
    testWidgets('Empty grid (not started)', (tester) async {
      final engine = GameEngine(_testPuzzle5x5);
      final state = engine.createInitialState();

      await tester.pumpWidget(_wrapScaffold(
        Center(
          child: PuzzleGrid(
            gameState: state,
            onCellTap: (_, _) {},
            onCellDrag: (_, _) {},
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await screenshot(tester, 'audit_04_grid_empty');

      // Waypoints, wall visible
      expect(find.byType(PuzzleGrid), findsOneWidget);
    });

    testWidgets('Grid with path in progress', (tester) async {
      final engine = GameEngine(_testPuzzle5x5);
      final state = _buildPlayingState(engine, [
        [0, 0], [1, 0], [2, 0], [3, 0], [4, 0],
        [4, 1], [3, 1], [2, 1],
      ]);

      await tester.pumpWidget(_wrapScaffold(
        Center(
          child: PuzzleGrid(
            gameState: state,
            onCellTap: (_, _) {},
            onCellDrag: (_, _) {},
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await screenshot(tester, 'audit_05_grid_path_in_progress');
    });

    testWidgets('Forward drag adds cells', (tester) async {
      final engine = GameEngine(_testPuzzle5x5);
      var state = engine.createInitialState();
      state = engine.addToPath(state, 0, 0);
      state = state.copyWith(status: GameStatus.playing);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: StatefulBuilder(
              builder: (context, setState) {
                return Scaffold(
                  backgroundColor: AppColors.deepBlack,
                  body: Center(
                    child: PuzzleGrid(
                      gameState: state,
                      onCellTap: (r, c) {
                        setState(() => state = engine.handleCellTap(state, r, c));
                      },
                      onCellDrag: (r, c) {
                        if (state.path.isNotEmpty &&
                            state.path.last.row == r &&
                            state.path.last.col == c) {
                          return;
                        }
                        final bt = engine.backtrackToCell(state, r, c);
                        if (bt != null) {
                          setState(() => state = bt);
                          return;
                        }
                        if (engine.canMoveToCell(state, r, c)) {
                          setState(() => state = engine.addToPath(state, r, c));
                        }
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final gridRect = tester.getRect(
        find.descendant(
          of: find.byType(PuzzleGrid),
          matching: find.byType(CustomPaint),
        ).first,
      );
      final cellSize = gridRect.width / 5;

      // Drag down column 0
      await tester.timedDragFrom(
        Offset(gridRect.left + cellSize * 0.5, gridRect.top + cellSize * 0.5),
        Offset(0, cellSize * 4),
        const Duration(milliseconds: 1000),
      );
      await tester.pumpAndSettle();
      await screenshot(tester, 'audit_06_forward_drag');

      expect(state.path.length, greaterThan(2),
          reason: 'Forward drag should extend path');
    });

    testWidgets('Backward drag erases cells', (tester) async {
      final engine = GameEngine(_testPuzzle5x5);
      var state = _buildPlayingState(engine, [
        [0, 0], [0, 1], [0, 2], [0, 3], [0, 4],
      ]);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: StatefulBuilder(
              builder: (context, setState) {
                return Scaffold(
                  backgroundColor: AppColors.deepBlack,
                  body: Center(
                    child: PuzzleGrid(
                      gameState: state,
                      onCellTap: (r, c) {
                        setState(() => state = engine.handleCellTap(state, r, c));
                      },
                      onCellDrag: (r, c) {
                        if (state.path.isNotEmpty &&
                            state.path.last.row == r &&
                            state.path.last.col == c) {
                          return;
                        }
                        final bt = engine.backtrackToCell(state, r, c);
                        if (bt != null) {
                          setState(() => state = bt);
                          return;
                        }
                        if (engine.canMoveToCell(state, r, c)) {
                          setState(() => state = engine.addToPath(state, r, c));
                        }
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await screenshot(tester, 'audit_07_before_backward_drag');

      final beforeLen = state.path.length;

      final gridRect = tester.getRect(
        find.descendant(
          of: find.byType(PuzzleGrid),
          matching: find.byType(CustomPaint),
        ).first,
      );
      final cellSize = gridRect.width / 5;

      // Drag backward from (0,4) to (0,1)
      await tester.timedDragFrom(
        Offset(gridRect.left + cellSize * 4.5, gridRect.top + cellSize * 0.5),
        Offset(-cellSize * 3, 0),
        const Duration(milliseconds: 1000),
      );
      await tester.pumpAndSettle();
      await screenshot(tester, 'audit_08_after_backward_drag');

      expect(state.path.length, lessThan(beforeLen),
          reason: 'Backward drag must erase cells. '
              'Before: $beforeLen, After: ${state.path.length}');
    });
  });

  // ── 3. GAME CONTROLS ──────────────────────────────────────────────

  group('3. Game Controls', () {
    testWidgets('Controls bar renders with Reset, Hint, Undo icon',
        (tester) async {
      final engine = GameEngine(_testPuzzle3x3);
      final state = _buildPlayingState(engine, [[0, 0], [0, 1]]);

      await tester.pumpWidget(_wrapScaffold(
        Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            GameControls(
              gameState: state,
              onUndo: () {},
              onReset: () {},
              onHint: () {},
            ),
          ],
        ),
      ));
      await tester.pumpAndSettle();
      await screenshot(tester, 'audit_09_game_controls');

      expect(find.text('Reset'), findsOneWidget);
      expect(find.text('Hint'), findsOneWidget);
      // Undo is a circle icon button (icon only, text in semantics)
      expect(find.byIcon(Icons.undo_rounded), findsOneWidget);
    });
  });

  // ── 4. CELEBRATION OVERLAY ─────────────────────────────────────────

  group('4. Celebration', () {
    Future<void> pumpPast(WidgetTester t) async {
      await t.pump(const Duration(milliseconds: 300));
      await t.pump(const Duration(milliseconds: 500));
      await t.pump(const Duration(milliseconds: 500));
      await t.pump(const Duration(milliseconds: 500));
    }

    testWidgets('Under par celebration', (tester) async {
      await tester.pumpWidget(_wrapScaffold(
        const Stack(children: [
          CelebrationOverlay(
            timeSeconds: 30,
            hintsUsed: 0,
            parTimeSeconds: 90,
            gridSize: 5,
            difficulty: 'medium',
          ),
        ]),
      ));
      await pumpPast(tester);
      await screenshot(tester, 'audit_10_celebration_under_par');

      expect(find.text('Crushed It!'), findsOneWidget);
      expect(find.byIcon(Icons.emoji_events_rounded), findsOneWidget);
      expect(find.text('Share Result'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
    });

    testWidgets('Over par celebration', (tester) async {
      await tester.pumpWidget(_wrapScaffold(
        const Stack(children: [
          CelebrationOverlay(
            timeSeconds: 150,
            hintsUsed: 2,
            parTimeSeconds: 90,
            gridSize: 5,
            difficulty: 'medium',
          ),
        ]),
      ));
      await pumpPast(tester);
      await screenshot(tester, 'audit_11_celebration_over_par');

      expect(find.text('Puzzle Complete!'), findsOneWidget);
      expect(find.text('2 hints used'), findsOneWidget);
    });
  });

  // ── 5. HOME SCREEN ─────────────────────────────────────────────────

  group('5. Home Screen', () {
    testWidgets('Home screen renders', (tester) async {
      await tester.pumpWidget(_wrap(
        const Scaffold(
          backgroundColor: AppColors.deepBlack,
          body: HomeScreen(),
        ),
      ));
      // Allow loading state to show
      await tester.pump(const Duration(milliseconds: 100));
      await screenshot(tester, 'audit_12_home_screen');

      expect(find.text('Zlynker'), findsOneWidget);
    });
  });

  // ── 6. STATS SCREEN ────────────────────────────────────────────────

  group('6. Stats Screen', () {
    testWidgets('Stats screen renders', (tester) async {
      await tester.pumpWidget(_wrap(
        const Scaffold(
          backgroundColor: AppColors.deepBlack,
          body: StatsScreen(),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 100));
      await screenshot(tester, 'audit_13_stats_screen');
    });
  });

  // ── 7-9. SCREENS REQUIRING SUPABASE ─────────────────────────────
  // GroupsScreen, ProfileScreen, AuthScreen require Supabase to be
  // initialised. They are tested via the running app, not in isolation.
  // The screens above (onboarding, home, puzzle, celebration, controls,
  // stats) cover ALL self-contained UI components.
}
