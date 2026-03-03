import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icos/core/constants/app_strings.dart';
import 'package:icos/features/home/presentation/home_screen.dart';
import 'package:icos/features/puzzle/domain/models/puzzle.dart';
import 'package:icos/features/puzzle/providers/daily_puzzle_provider.dart';

import '../../../helpers/test_helpers.dart';

void main() {
  group('HomeScreen', () {
    Widget buildHomeScreen({
      AsyncValue<Puzzle>? puzzleState,
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
        ],
      );
    }

    group('Header content', () {
      testWidgets('shows app name "Icos"', (tester) async {
        await tester.pumpWidget(buildHomeScreen());
        await tester.pumpAndSettle();

        expect(find.text(AppStrings.appName), findsOneWidget);
      });

      testWidgets('shows app tagline "Daily Path Puzzle"', (tester) async {
        await tester.pumpWidget(buildHomeScreen());
        await tester.pumpAndSettle();

        expect(find.text(AppStrings.appTagline), findsOneWidget);
      });
    });

    group('Puzzle card with data', () {
      testWidgets('shows puzzle title "Today\'s Puzzle"', (tester) async {
        await tester.pumpWidget(buildHomeScreen());
        await tester.pumpAndSettle();

        expect(find.text(AppStrings.puzzleTitle), findsOneWidget);
      });

      testWidgets('shows grid size and difficulty', (tester) async {
        await tester.pumpWidget(buildHomeScreen());
        await tester.pumpAndSettle();

        // testPuzzle is 5x5 Easy
        expect(find.textContaining('5x5'), findsOneWidget);
        expect(find.textContaining('Easy'), findsOneWidget);
      });

      testWidgets('shows grid icon', (tester) async {
        await tester.pumpWidget(buildHomeScreen());
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.grid_4x4_rounded), findsOneWidget);
      });

      testWidgets('shows Play button', (tester) async {
        await tester.pumpWidget(buildHomeScreen());
        await tester.pumpAndSettle();

        expect(find.text('Play'), findsOneWidget);
      });

      testWidgets('Play button is an ElevatedButton', (tester) async {
        await tester.pumpWidget(buildHomeScreen());
        await tester.pumpAndSettle();

        final playButton = find.ancestor(
          of: find.text('Play'),
          matching: find.byType(ElevatedButton),
        );
        expect(playButton, findsOneWidget);
      });
    });

    group('Loading state', () {
      testWidgets('shows app name during loading', (tester) async {
        // Override with a provider that starts loading
        await tester.pumpWidget(buildHomeScreen());

        // Only pump once so the loading state may still be shown
        await tester.pump();

        // App name should be visible even during loading
        expect(find.text(AppStrings.appName), findsOneWidget);
        expect(find.text(AppStrings.appTagline), findsOneWidget);
      });
    });

    group('Error state', () {
      testWidgets('shows puzzle card even on error (fallback)', (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              dailyPuzzleProvider.overrideWith(
                (ref) async {
                  throw Exception('Network error');
                },
              ),
            ],
            child: MaterialApp(
              home: const HomeScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // On error, the HomeScreen shows a fallback puzzle card with default values
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

      testWidgets('has a Card widget for puzzle display', (tester) async {
        await tester.pumpWidget(buildHomeScreen());
        await tester.pumpAndSettle();

        expect(find.byType(Card), findsOneWidget);
      });

      testWidgets('card is constrained to contentMaxWidth', (tester) async {
        await tester.pumpWidget(buildHomeScreen());
        await tester.pumpAndSettle();

        // Find ConstrainedBox widgets; there should be at least one
        // with the contentMaxWidth constraint
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
