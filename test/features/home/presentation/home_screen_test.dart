import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:icos/core/constants/app_sizes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icos/core/constants/app_strings.dart';
import 'package:icos/core/theme/app_theme.dart';
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
      ThemeData? theme,
      bool inScaffold = false,
    }) {
      return buildTestWidget(
        inScaffold ? const Scaffold(body: HomeScreen()) : const HomeScreen(),
        theme: theme,
        overrides: [
          dailyPuzzleProvider.overrideWith((ref) async {
            if (puzzleState is AsyncError) {
              throw (puzzleState as AsyncError).error!;
            }
            return testPuzzle;
          }),
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

    group('Practice and Archive cards', () {
      // The default test font is a fixed-width box font; the app uses Inter.
      setUpAll(() async {
        final loader = FontLoader('Inter');
        for (final weight in ['Regular', 'Bold']) {
          loader.addFont(
            Future.value(
              ByteData.sublistView(
                File('assets/google_fonts/Inter-$weight.ttf').readAsBytesSync(),
              ),
            ),
          );
        }
        await loader.load();
      });

      Future<void> pumpAt(WidgetTester tester, Size size, double scale) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: TextScaler.linear(scale),
            ),
            child: buildHomeScreen(
              inScaffold: true,
              theme: AppTheme.darkTheme.copyWith(
                textTheme: AppTheme.darkTheme.textTheme.apply(
                  fontFamily: 'Inter',
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(const Key('home-archive')),
          200,
          scrollable: find.byType(Scrollable).first,
        );
      }

      /// Every word of every card label must sit on a single line.
      void expectNoMidWordBreaks(WidgetTester tester) {
        for (final key in const ['home-practice', 'home-archive']) {
          final texts = find.descendant(
            of: find.byKey(Key(key)),
            matching: find.byType(Text),
          );
          expect(texts, findsNWidgets(2));
          for (final element in texts.evaluate()) {
            final paragraph = element.renderObject! as RenderParagraph;
            final text = paragraph.text.toPlainText();
            var start = 0;
            for (final word in text.split(' ')) {
              final boxes = paragraph.getBoxesForSelection(
                TextSelection(
                  baseOffset: start,
                  extentOffset: start + word.length,
                ),
              );
              expect(
                boxes.map((b) => b.top.round()).toSet().length,
                1,
                reason: '"$word" in "$text" is split across lines',
              );
              start += word.length + 1;
            }
          }
        }
      }

      testWidgets('sit side by side at normal text size on 393x852', (
        tester,
      ) async {
        await pumpAt(tester, const Size(393, 852), 1);

        final practice = tester.getRect(find.byKey(const Key('home-practice')));
        final archive = tester.getRect(find.byKey(const Key('home-archive')));
        // One row: the rects overlap vertically (heights may differ).
        expect(practice.bottom, greaterThan(archive.top));
        expect(archive.bottom, greaterThan(practice.top));
        expect(practice.right, lessThan(archive.left));
        expectNoMidWordBreaks(tester);
      });

      for (final size in const [Size(320, 568), Size(393, 852)]) {
        testWidgets('stack full width without mid-word breaks at 200% on '
            '${size.width.toInt()}x${size.height.toInt()}', (tester) async {
          await pumpAt(tester, size, 2);

          final practice = tester.getRect(
            find.byKey(const Key('home-practice')),
          );
          final archive = tester.getRect(find.byKey(const Key('home-archive')));
          expect(archive.top, greaterThanOrEqualTo(practice.bottom));
          expect(practice.width, archive.width);
          expectNoMidWordBreaks(tester);
        });
      }
    });

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

      testWidgets('shows a streak badge when the streak is positive', (
        tester,
      ) async {
        await tester.pumpWidget(buildHomeScreen(streak: 6));
        await tester.pumpAndSettle();

        expect(find.text('6'), findsOneWidget);
        expect(
          find.byIcon(Icons.local_fire_department_rounded),
          findsOneWidget,
        );
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
      testWidgets('shows summary with time, hints and rank plus Share/View', (
        tester,
      ) async {
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

      testWidgets('prefers the streak returned with the result', (
        tester,
      ) async {
        await tester.pumpWidget(
          buildHomeScreen(result: solvedResult, streak: 1),
        );
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

      testWidgets('hides Play while the result is still loading', (
        tester,
      ) async {
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
            puzzleState: AsyncError(
              Exception('Network error'),
              StackTrace.empty,
            ),
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
          (box) => box.constraints.maxWidth == AppSizes.contentMaxWidth,
        );
        expect(hasContentMaxWidth, isTrue);
      });
    });
  });
}
