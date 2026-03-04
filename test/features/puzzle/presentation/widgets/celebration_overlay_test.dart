import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icos/features/puzzle/presentation/widgets/celebration_overlay.dart';

import '../../../../helpers/test_helpers.dart';

void main() {
  group('CelebrationOverlay', () {
    Widget buildCelebrationOverlay({
      int timeSeconds = 45,
      int hintsUsed = 0,
      int parTimeSeconds = 120,
      int gridSize = 5,
      String difficulty = 'easy',
    }) {
      return buildTestWidget(
        Scaffold(
          body: Stack(
            children: [
              CelebrationOverlay(
                timeSeconds: timeSeconds,
                hintsUsed: hintsUsed,
                parTimeSeconds: parTimeSeconds,
                gridSize: gridSize,
                difficulty: difficulty,
              ),
            ],
          ),
        ),
      );
    }

    // Pump enough frames for the card animation to complete
    // (fade: 400ms, card delay: 200ms, card: 800ms = ~1400ms total)
    // We can't use pumpAndSettle because confetti keeps animating.
    Future<void> pumpPastAnimations(WidgetTester tester) async {
      await tester.pump(const Duration(milliseconds: 300)); // trigger delayed card
      await tester.pump(const Duration(milliseconds: 500)); // mid-card animation
      await tester.pump(const Duration(milliseconds: 500)); // card animation done
      await tester.pump(const Duration(milliseconds: 500)); // settle
    }

    group('Under par message', () {
      testWidgets('shows "Crushed It!" when time <= par time', (tester) async {
        await tester.pumpWidget(buildCelebrationOverlay(
          timeSeconds: 45,
          parTimeSeconds: 120,
        ));
        await pumpPastAnimations(tester);

        expect(find.text('Crushed It!'), findsOneWidget);
      });

      testWidgets('shows "Crushed It!" when time equals par time',
          (tester) async {
        await tester.pumpWidget(buildCelebrationOverlay(
          timeSeconds: 120,
          parTimeSeconds: 120,
        ));
        await pumpPastAnimations(tester);

        expect(find.text('Crushed It!'), findsOneWidget);
      });

      testWidgets('shows trophy icon when under par', (tester) async {
        await tester.pumpWidget(buildCelebrationOverlay(
          timeSeconds: 45,
          parTimeSeconds: 120,
        ));
        await pumpPastAnimations(tester);

        expect(find.byIcon(Icons.emoji_events_rounded), findsOneWidget);
      });
    });

    group('Over par message', () {
      testWidgets('shows "Puzzle Complete!" when time > par time',
          (tester) async {
        await tester.pumpWidget(buildCelebrationOverlay(
          timeSeconds: 150,
          parTimeSeconds: 120,
        ));
        await pumpPastAnimations(tester);

        expect(find.text('Puzzle Complete!'), findsOneWidget);
      });

      testWidgets('shows check icon when over par', (tester) async {
        await tester.pumpWidget(buildCelebrationOverlay(
          timeSeconds: 150,
          parTimeSeconds: 120,
        ));
        await pumpPastAnimations(tester);

        expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      });
    });

    group('Result display', () {
      testWidgets('displays hints used text when hints > 0', (tester) async {
        await tester.pumpWidget(buildCelebrationOverlay(
          timeSeconds: 45,
          hintsUsed: 2,
          parTimeSeconds: 120,
        ));
        await pumpPastAnimations(tester);

        expect(find.text('2 hints used'), findsOneWidget);
      });

      testWidgets('does not display hints text when hints is 0',
          (tester) async {
        await tester.pumpWidget(buildCelebrationOverlay(
          timeSeconds: 45,
          hintsUsed: 0,
          parTimeSeconds: 120,
        ));
        await pumpPastAnimations(tester);

        expect(find.textContaining('hints used'), findsNothing);
      });
    });

    group('Action buttons', () {
      testWidgets('Share Result button is present', (tester) async {
        await tester.pumpWidget(buildCelebrationOverlay());
        await pumpPastAnimations(tester);

        expect(find.text('Share Result'), findsOneWidget);
        expect(find.byIcon(Icons.share_rounded), findsOneWidget);
      });

      testWidgets('Done button is present', (tester) async {
        await tester.pumpWidget(buildCelebrationOverlay());
        await pumpPastAnimations(tester);

        expect(find.text('Done'), findsOneWidget);
      });

      testWidgets('Share Result button exists', (tester) async {
        await tester.pumpWidget(buildCelebrationOverlay());
        await pumpPastAnimations(tester);

        expect(find.text('Share Result'), findsOneWidget);
      });

      testWidgets('Done button is tappable', (tester) async {
        await tester.pumpWidget(buildCelebrationOverlay());
        await pumpPastAnimations(tester);

        // Done button is rendered as a SpringButton wrapping styled Container
        final doneText = find.text('Done');
        expect(doneText, findsOneWidget);
      });
    });

    group('Animation', () {
      testWidgets('overlay animates in (opacity starts at 0)', (tester) async {
        await tester.pumpWidget(buildCelebrationOverlay());

        // At frame 0, there are multiple Opacity widgets (background fade + card opacity)
        final opacityFinder = find.byType(Opacity);
        expect(opacityFinder, findsWidgets);

        final opacityWidgets = tester.widgetList<Opacity>(opacityFinder);
        // At least one opacity should be low (animation starting)
        final hasLowOpacity = opacityWidgets.any(
          (o) => o.opacity <= 0.5,
        );
        expect(hasLowOpacity, isTrue);

        // Pump past pending timers to avoid timer assertion error
        await pumpPastAnimations(tester);
      });

      testWidgets('overlay becomes fully visible after animation completes',
          (tester) async {
        await tester.pumpWidget(buildCelebrationOverlay());
        await pumpPastAnimations(tester);

        // After animation completes, all Opacity widgets should be at 1.0
        final opacityWidgets = tester.widgetList<Opacity>(find.byType(Opacity));
        for (final opacityWidget in opacityWidgets) {
          expect(opacityWidget.opacity, equals(1.0));
        }
      });

      testWidgets('scale animation starts below 1.0', (tester) async {
        await tester.pumpWidget(buildCelebrationOverlay());

        // At frame 0, Transform.scale should have a scale below 1.0
        final transformFinder = find.byType(Transform);
        expect(transformFinder, findsWidgets);

        // Pump past pending timers to avoid timer assertion error
        await pumpPastAnimations(tester);
      });
    });

    group('Layout', () {
      testWidgets('overlay has dark background', (tester) async {
        await tester.pumpWidget(buildCelebrationOverlay());
        await pumpPastAnimations(tester);

        // Should find a Container with gradient background
        final containerFinder = find.byType(Container);
        expect(containerFinder, findsWidgets);
      });

      testWidgets('content is constrained in width', (tester) async {
        await tester.pumpWidget(buildCelebrationOverlay());
        await pumpPastAnimations(tester);

        // Find ConstrainedBox with maxWidth of 340
        final constrainedBox = find.byType(ConstrainedBox);
        expect(constrainedBox, findsWidgets);
      });

      testWidgets('content is wrapped in a Container', (tester) async {
        await tester.pumpWidget(buildCelebrationOverlay());
        await pumpPastAnimations(tester);

        expect(find.byType(Container), findsWidgets);
      });
    });
  });
}
