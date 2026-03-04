import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icos/features/puzzle/domain/models/game_state.dart';
import 'package:icos/features/puzzle/presentation/widgets/game_controls.dart';

import '../../../../helpers/test_helpers.dart';

void main() {
  group('GameControls', () {
    late bool undoCalled;
    late bool resetCalled;
    late bool hintCalled;

    setUp(() {
      undoCalled = false;
      resetCalled = false;
      hintCalled = false;
    });

    Widget buildGameControls(GameState gameState) {
      return buildTestWidgetInScaffold(
        GameControls(
          gameState: gameState,
          onUndo: () => undoCalled = true,
          onReset: () => resetCalled = true,
          onHint: () => hintCalled = true,
        ),
      );
    }

    group('Rendering', () {
      testWidgets('renders Undo button', (tester) async {
        final state = createPlayingGameState();
        await tester.pumpWidget(buildGameControls(state));

        expect(find.byIcon(Icons.undo_rounded), findsOneWidget);
      });

      testWidgets('renders Reset button', (tester) async {
        final state = createPlayingGameState();
        await tester.pumpWidget(buildGameControls(state));

        expect(find.text('Reset'), findsOneWidget);
        expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
      });

      testWidgets('renders Hint button', (tester) async {
        final state = createPlayingGameState();
        await tester.pumpWidget(buildGameControls(state));

        expect(find.text('Hint'), findsOneWidget);
      });
    });

    group('Button states when NOT playing', () {
      testWidgets('undo and reset are disabled when status is notStarted',
          (tester) async {
        final state = createNotStartedGameState();
        await tester.pumpWidget(buildGameControls(state));

        // Tap each button - callbacks should NOT fire
        await tester.tap(find.byIcon(Icons.undo_rounded));
        await tester.tap(find.text('Reset'));
        expect(undoCalled, isFalse);
        expect(resetCalled, isFalse);
      });

      testWidgets('hint button is enabled when status is notStarted',
          (tester) async {
        final state = createNotStartedGameState();
        await tester.pumpWidget(buildGameControls(state));

        await tester.tap(find.text('Hint'));
        expect(hintCalled, isTrue);
      });

      testWidgets('buttons are disabled when status is completed',
          (tester) async {
        final state = createCompletedGameState();
        await tester.pumpWidget(buildGameControls(state));

        await tester.tap(find.byIcon(Icons.undo_rounded));
        await tester.tap(find.text('Reset'));
        await tester.tap(find.text('Hint'));
        expect(undoCalled, isFalse);
        expect(resetCalled, isFalse);
        expect(hintCalled, isFalse);
      });
    });

    group('Button states when playing with path', () {
      testWidgets('undo button is enabled and fires callback', (tester) async {
        final state = createPlayingGameState();
        await tester.pumpWidget(buildGameControls(state));

        await tester.tap(find.byIcon(Icons.undo_rounded));
        expect(undoCalled, isTrue);
      });

      testWidgets('reset button is enabled and fires callback',
          (tester) async {
        final state = createPlayingGameState();
        await tester.pumpWidget(buildGameControls(state));

        await tester.tap(find.text('Reset'));
        expect(resetCalled, isTrue);
      });

      testWidgets('hint button is enabled and fires callback',
          (tester) async {
        final state = createPlayingGameState();
        await tester.pumpWidget(buildGameControls(state));

        await tester.tap(find.text('Hint'));
        expect(hintCalled, isTrue);
      });
    });

    group('Button states when playing WITHOUT path', () {
      testWidgets(
          'undo and reset are disabled when path is empty but status is playing',
          (tester) async {
        // Create a playing state with empty path
        final state = createNotStartedGameState().copyWith(
          status: GameStatus.playing,
        );
        await tester.pumpWidget(buildGameControls(state));

        await tester.tap(find.byIcon(Icons.undo_rounded));
        await tester.tap(find.text('Reset'));
        expect(undoCalled, isFalse);
        expect(resetCalled, isFalse);
      });

      testWidgets('hint is enabled even when path is empty but playing',
          (tester) async {
        final state = createNotStartedGameState().copyWith(
          status: GameStatus.playing,
        );
        await tester.pumpWidget(buildGameControls(state));

        await tester.tap(find.text('Hint'));
        expect(hintCalled, isTrue);
      });
    });

    group('Badge count', () {
      testWidgets('shows badge with hint count when hints used > 0',
          (tester) async {
        final state = createPlayingGameState(hintsUsed: 3);
        await tester.pumpWidget(buildGameControls(state));

        // Badge shows the hint count
        expect(find.text('3'), findsOneWidget);
      });

      testWidgets('does not show badge when hint count is 0',
          (tester) async {
        final state = createPlayingGameState(hintsUsed: 0);
        await tester.pumpWidget(buildGameControls(state));

        // Badge with '0' should not be visible
        expect(find.text('0'), findsNothing);
      });

      testWidgets('shows badge with count of 1', (tester) async {
        final state = createPlayingGameState(hintsUsed: 1);
        await tester.pumpWidget(buildGameControls(state));

        expect(find.text('1'), findsOneWidget);
      });
    });

    group('Accessibility', () {
      testWidgets('undo button has Semantics widget with label',
          (tester) async {
        final state = createPlayingGameState();
        await tester.pumpWidget(buildGameControls(state));

        // The _ControlButton wraps InkWell with Semantics(button: true, label: 'Undo')
        final semanticsWidgets = tester.widgetList<Semantics>(
          find.byType(Semantics),
        );
        final hasUndoLabel = semanticsWidgets.any(
          (s) => s.properties.label == 'Undo' && s.properties.button == true,
        );
        expect(hasUndoLabel, isTrue);
      });

      testWidgets('reset button has Semantics widget with label',
          (tester) async {
        final state = createPlayingGameState();
        await tester.pumpWidget(buildGameControls(state));

        final semanticsWidgets = tester.widgetList<Semantics>(
          find.byType(Semantics),
        );
        final hasResetLabel = semanticsWidgets.any(
          (s) => s.properties.label == 'Reset' && s.properties.button == true,
        );
        expect(hasResetLabel, isTrue);
      });

      testWidgets('hint button has Semantics widget with label',
          (tester) async {
        final state = createPlayingGameState();
        await tester.pumpWidget(buildGameControls(state));

        final semanticsWidgets = tester.widgetList<Semantics>(
          find.byType(Semantics),
        );
        final hasHintLabel = semanticsWidgets.any(
          (s) => s.properties.label == 'Hint' && s.properties.button == true,
        );
        expect(hasHintLabel, isTrue);
      });
    });
  });
}
