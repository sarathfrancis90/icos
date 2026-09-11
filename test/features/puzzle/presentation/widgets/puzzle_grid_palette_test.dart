import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icos/features/puzzle/domain/models/game_state.dart';
import 'package:icos/features/puzzle/presentation/widgets/grid_palette.dart';
import 'package:icos/features/puzzle/presentation/widgets/puzzle_grid.dart';
import 'package:icos/features/puzzle/providers/colorblind_mode_provider.dart';

import '../../../../helpers/test_helpers.dart';

void main() {
  group('GridPalette', () {
    test('forMode maps every mode and flags patterns for colorblind modes', () {
      expect(GridPalette.forMode(ColorblindMode.none).patterns, isFalse);
      for (final mode in ColorblindMode.values.where((m) => m.isActive)) {
        final palette = GridPalette.forMode(mode);
        expect(palette.mode, mode);
        expect(palette.patterns, isTrue);
        expect(palette.pathGradient, hasLength(5));
        expect(
          palette.waypointFill,
          isNot(palette.pathHead),
          reason: 'waypoints must contrast with the path in $mode',
        );
      }
    });

    test('ColorblindMode.parse is lenient', () {
      expect(ColorblindMode.parse('tritanopia'), ColorblindMode.tritanopia);
      expect(ColorblindMode.parse('garbage'), ColorblindMode.none);
      expect(ColorblindMode.parse(null), ColorblindMode.none);
    });
  });

  group('PuzzleGrid with palettes', () {
    for (final palette in [
      GridPalette.standard,
      GridPalette.deuteranopia,
      GridPalette.protanopia,
      GridPalette.tritanopia,
    ]) {
      testWidgets('paints ${palette.mode.name} palette with a wrong cell',
          (tester) async {
        var taps = 0;
        await tester.pumpWidget(
          buildTestWidgetInScaffold(
            PuzzleGrid(
              gameState: createPlayingGameState(),
              palette: palette,
              wrongCell: const GridPosition(row: 0, col: 1),
              onCellTap: (_, _) => taps++,
              onCellDrag: (_, _) {},
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        expect(find.byType(PuzzleGrid), findsOneWidget);

        await tester.tap(find.bySemanticsLabel('Row 1, Column 3, empty'));
        expect(taps, 1);
      });
    }

    testWidgets('readOnly ignores taps', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        buildTestWidgetInScaffold(
          PuzzleGrid(
            gameState: createPlayingGameState(),
            readOnly: true,
            onCellTap: (_, _) => taps++,
            onCellDrag: (_, _) {},
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Row 1, Column 3, empty'));
      expect(taps, 0);
    });
  });
}
