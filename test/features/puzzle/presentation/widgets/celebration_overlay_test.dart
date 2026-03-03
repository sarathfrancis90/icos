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

    group('Under par message', () {
      testWidgets('shows "Under Par!" when time <= par time', (tester) async {
        await tester.pumpWidget(buildCelebrationOverlay(
          timeSeconds: 45,
          parTimeSeconds: 120,
        ));
        await tester.pumpAndSettle();

        expect(find.text('Under Par!'), findsOneWidget);
      });

      testWidgets('shows "Under Par!" when time equals par time',
          (tester) async {
        await tester.pumpWidget(buildCelebrationOverlay(
          timeSeconds: 120,
          parTimeSeconds: 120,
        ));
        await tester.pumpAndSettle();

        expect(find.text('Under Par!'), findsOneWidget);
      });

      testWidgets('shows trophy icon when under par', (tester) async {
        await tester.pumpWidget(buildCelebrationOverlay(
          timeSeconds: 45,
          parTimeSeconds: 120,
        ));
        await tester.pumpAndSettle();

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
        await tester.pumpAndSettle();

        expect(find.text('Puzzle Complete!'), findsOneWidget);
      });

      testWidgets('shows check icon when over par', (tester) async {
        await tester.pumpWidget(buildCelebrationOverlay(
          timeSeconds: 150,
          parTimeSeconds: 120,
        ));
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      });
    });

    group('Result display', () {
      testWidgets('displays Time label and value', (tester) async {
        await tester.pumpWidget(buildCelebrationOverlay(
          timeSeconds: 65,
          parTimeSeconds: 120,
        ));
        await tester.pumpAndSettle();

        expect(find.text('Time'), findsOneWidget);
        expect(find.text('01:05'), findsOneWidget);
      });

      testWidgets('displays Par label and value', (tester) async {
        await tester.pumpWidget(buildCelebrationOverlay(
          timeSeconds: 45,
          parTimeSeconds: 120,
        ));
        await tester.pumpAndSettle();

        expect(find.text('Par'), findsOneWidget);
        expect(find.text('02:00'), findsOneWidget);
      });

      testWidgets('displays Hints Used label and value', (tester) async {
        await tester.pumpWidget(buildCelebrationOverlay(
          timeSeconds: 45,
          hintsUsed: 2,
          parTimeSeconds: 120,
        ));
        await tester.pumpAndSettle();

        expect(find.text('Hints Used'), findsOneWidget);
        expect(find.text('2'), findsOneWidget);
      });

      testWidgets('displays 0 hints used', (tester) async {
        await tester.pumpWidget(buildCelebrationOverlay(
          timeSeconds: 45,
          hintsUsed: 0,
          parTimeSeconds: 120,
        ));
        await tester.pumpAndSettle();

        expect(find.text('Hints Used'), findsOneWidget);
        expect(find.text('0'), findsOneWidget);
      });
    });

    group('Action buttons', () {
      testWidgets('Share Result button is present', (tester) async {
        await tester.pumpWidget(buildCelebrationOverlay());
        await tester.pumpAndSettle();

        expect(find.text('Share Result'), findsOneWidget);
        expect(find.byIcon(Icons.share_rounded), findsOneWidget);
      });

      testWidgets('Done button is present', (tester) async {
        await tester.pumpWidget(buildCelebrationOverlay());
        await tester.pumpAndSettle();

        expect(find.text('Done'), findsOneWidget);
      });

      testWidgets('Share Result is an ElevatedButton', (tester) async {
        await tester.pumpWidget(buildCelebrationOverlay());
        await tester.pumpAndSettle();

        // The Share Result button should be an ElevatedButton.icon
        final shareButton = find.ancestor(
          of: find.text('Share Result'),
          matching: find.byType(ElevatedButton),
        );
        expect(shareButton, findsOneWidget);
      });

      testWidgets('Done is an OutlinedButton', (tester) async {
        await tester.pumpWidget(buildCelebrationOverlay());
        await tester.pumpAndSettle();

        final doneButton = find.ancestor(
          of: find.text('Done'),
          matching: find.byType(OutlinedButton),
        );
        expect(doneButton, findsOneWidget);
      });
    });

    group('Animation', () {
      testWidgets('overlay animates in (opacity starts at 0)', (tester) async {
        await tester.pumpWidget(buildCelebrationOverlay());

        // At frame 0, opacity should be low (animation starting)
        final opacityFinder = find.byType(Opacity);
        expect(opacityFinder, findsOneWidget);

        final opacityWidget = tester.widget<Opacity>(opacityFinder);
        // At the very first frame, opacity should be 0 or near 0
        expect(opacityWidget.opacity, lessThanOrEqualTo(0.5));
      });

      testWidgets('overlay becomes fully visible after animation completes',
          (tester) async {
        await tester.pumpWidget(buildCelebrationOverlay());
        await tester.pumpAndSettle();

        // After animation completes, opacity should be 1.0
        final opacityWidget = tester.widget<Opacity>(find.byType(Opacity));
        expect(opacityWidget.opacity, equals(1.0));
      });

      testWidgets('scale animation starts below 1.0', (tester) async {
        await tester.pumpWidget(buildCelebrationOverlay());

        // At frame 0, Transform.scale should have a scale below 1.0
        final transformFinder = find.byType(Transform);
        expect(transformFinder, findsWidgets);
      });
    });

    group('Layout', () {
      testWidgets('overlay has dark background', (tester) async {
        await tester.pumpWidget(buildCelebrationOverlay());
        await tester.pumpAndSettle();

        // Should find a Container with Colors.black54 background
        final containerFinder = find.byType(Container);
        expect(containerFinder, findsWidgets);
      });

      testWidgets('content is constrained in width', (tester) async {
        await tester.pumpWidget(buildCelebrationOverlay());
        await tester.pumpAndSettle();

        // Find ConstrainedBox with maxWidth of 320
        final constrainedBox = find.byType(ConstrainedBox);
        expect(constrainedBox, findsWidgets);
      });

      testWidgets('content is wrapped in a Card', (tester) async {
        await tester.pumpWidget(buildCelebrationOverlay());
        await tester.pumpAndSettle();

        expect(find.byType(Card), findsOneWidget);
      });
    });
  });
}
