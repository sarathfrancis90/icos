import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icos/core/constants/app_strings.dart';
import 'package:icos/features/home/presentation/home_screen.dart';
import 'package:icos/features/puzzle/data/submission_result.dart';
import 'package:icos/features/puzzle/domain/models/puzzle.dart';
import 'package:icos/features/puzzle/providers/daily_puzzle_provider.dart';
import 'package:icos/features/puzzle/providers/puzzle_result_provider.dart';
import 'package:icos/features/stats/domain/models/streak.dart';
import 'package:icos/features/stats/providers/stats_provider.dart';

import '../../../helpers/test_helpers.dart';

void main() {
  final solvedResult = SubmissionResult(
    date: '2026-09-09',
    status: SubmissionStatus.verified,
    timeSeconds: 45,
    hintsUsed: 0,
    undosUsed: 2,
    path: const [
      [0, 0],
      [0, 1],
    ],
    completedAt: DateTime.utc(2026, 9, 9, 10),
    streak: const StreakSnapshot(
      currentStreak: 4,
      longestStreak: 4,
      freezeCount: 1,
    ),
    rankHint: 3,
  );

  group('HomeScreen', () {
    Widget buildHomeScreen({
      AsyncValue<Puzzle>? puzzleState,
      SubmissionResult? result,
      bool resultPending = false,
      int streak = 0,
    }) {
      return buildTestWidget(
        const HomeScreen(),
        overrides: [
          dailyPuzzleProvider.overrideWith(
            (ref) async {
              if (puzzleState is AsyncError) {
                throw (puzzleState as AsyncError).error!;
              }
              return testPuzzle;
            },
          ),
          todayResultProvider.overrideWith((ref) async {
            if (resultPending) await Completer<SubmissionResult?>().future;
            return result;
          }),
          streakProvider.overrideWith(
            (ref) async => Streak(
              userId: 'u',
              currentStreak: streak,
              longestStreak: streak,
              freezeCount: 1,
            ),
          ),
        ],
      );
    }

    group('Header content', () {
      testWidgets('shows app name "Icos"', (tester) async {
        await tester.pumpWidget(buildHomeScreen());
        await tester.pumpAndSettle();

        expect(find.text(AppStrings.appName), findsOneWidget);
      });

      testWidgets('shows app tagline', (tester) async {
        await tester.pumpWidget(buildHomeScreen());
        await tester.pumpAndSettle();

        expect(find.text(AppStrings.appTagline), findsOneWidget);
      });

      testWidgets('shows a streak badge when the streak is positive',
          (tester) async {
        await tester.pumpWidget(buildHomeScreen(streak: 6));
        await tester.pumpAndSettle();

        expect(find.text('6'), findsOneWidget);
        expect(find.byIcon(Icons.local_fire_department_rounded), findsOneWidget);
      });
    });

    group('Unsolved state', () {
      testWidgets('shows puzzle title, grid info and Play', (tester) async {
        await tester.pumpWidget(buildHomeScreen());
        await tester.pumpAndSettle();

        expect(find.text(AppStrings.puzzleTitle), findsOneWidget);
        expect(find.textContaining('5x5'), findsOneWidget);
        expect(find.textContaining('Easy'), findsOneWidget);
        expect(find.byIcon(Icons.grid_4x4_rounded), findsOneWidget);
        expect(find.byKey(const Key('home-play')), findsOneWidget);
        expect(find.text('Play'), findsOneWidget);
        expect(find.byKey(const Key('home-share')), findsNothing);
        expect(find.byKey(const Key('home-view')), findsNothing);
      });

      testWidgets('shows Practice and Archive entry points', (tester) async {
        await tester.pumpWidget(buildHomeScreen());
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('home-practice')), findsOneWidget);
        expect(find.byKey(const Key('home-archive')), findsOneWidget);
        expect(find.text('Practice'), findsOneWidget);
        expect(find.text('Archive'), findsOneWidget);
      });
    });

    group('Solved state', () {
      testWidgets('shows summary with time, hints and rank plus Share/View',
          (tester) async {
        await tester.pumpWidget(buildHomeScreen(result: solvedResult));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('home-solved-summary')), findsOneWidget);
        expect(
          find.text('Solved in 00:45 · 0 hints · #3 today'),
          findsOneWidget,
        );
        expect(find.byKey(const Key('home-share')), findsOneWidget);
        expect(find.byKey(const Key('home-view')), findsOneWidget);
        expect(find.byKey(const Key('home-play')), findsNothing);
        expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      });

      testWidgets('prefers the streak returned with the result', (tester) async {
        await tester.pumpWidget(buildHomeScreen(result: solvedResult, streak: 1));
        await tester.pumpAndSettle();

        expect(find.text('4'), findsOneWidget);
      });

      testWidgets('rejected result shows a "not counted" note', (tester) async {
        await tester.pumpWidget(
          buildHomeScreen(
            result: solvedResult.copyWith(
              status: SubmissionStatus.rejected,
              reason: 'BAD_SIGNATURE',
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('Not counted'), findsOneWidget);
        expect(find.byKey(const Key('home-view')), findsOneWidget);
      });

      testWidgets('pending result shows a saving note', (tester) async {
        await tester.pumpWidget(
          buildHomeScreen(
            result: solvedResult.copyWith(status: SubmissionStatus.pending),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Saving result…'), findsOneWidget);
      });
    });

    group('Loading state', () {
      testWidgets('shows app name during loading', (tester) async {
        await tester.pumpWidget(buildHomeScreen());
        await tester.pump();

        expect(find.text(AppStrings.appName), findsOneWidget);
        expect(find.text(AppStrings.appTagline), findsOneWidget);
      });

      testWidgets('hides Play while the result is still loading',
          (tester) async {
        await tester.pumpWidget(buildHomeScreen(resultPending: true));
        await tester.pump();
        await tester.pump();

        expect(find.text(AppStrings.puzzleTitle), findsOneWidget);
        expect(find.byKey(const Key('home-play')), findsNothing);
      });
    });

    group('Error state', () {
      testWidgets('shows puzzle card even on error (fallback)', (tester) async {
        await tester.pumpWidget(
          buildHomeScreen(
            puzzleState: AsyncError(Exception('Network error'), StackTrace.empty),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text(AppStrings.puzzleTitle), findsOneWidget);
        expect(find.text('Play'), findsOneWidget);
      });
    });

    group('Layout structure', () {
      testWidgets('has SafeArea', (tester) async {
        await tester.pumpWidget(buildHomeScreen());
        await tester.pumpAndSettle();

        expect(find.byType(SafeArea), findsOneWidget);
      });

      testWidgets('card is constrained to contentMaxWidth', (tester) async {
        await tester.pumpWidget(buildHomeScreen());
        await tester.pumpAndSettle();

        final constrainedBoxes = tester.widgetList<ConstrainedBox>(
          find.byType(ConstrainedBox),
        );
        final hasContentMaxWidth = constrainedBoxes.any(
          (box) => box.constraints.maxWidth == 600.0,
        );
        expect(hasContentMaxWidth, isTrue);
      });
    });
  });
}
