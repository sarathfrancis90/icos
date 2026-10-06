import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icos/core/constants/app_strings.dart';
import 'package:icos/core/theme/app_palette.dart';
import 'package:icos/core/theme/app_theme.dart';
import 'package:icos/features/puzzle/presentation/widgets/first_play_tooltip.dart';
import 'package:icos/features/puzzle/presentation/widgets/grid_palette.dart';
import 'package:icos/features/puzzle/presentation/widgets/puzzle_grid.dart';
import 'package:icos/features/puzzle/providers/colorblind_mode_provider.dart';

import '../../../../helpers/contrast.dart';
import '../../../../helpers/test_helpers.dart';

Widget _grid({required bool cue, bool reduceMotion = false}) {
  return MediaQuery(
    data: MediaQueryData(
      size: const Size(400, 800),
      disableAnimations: reduceMotion,
    ),
    child: buildTestWidgetInScaffold(
      PuzzleGrid(
        gameState: createPlayingGameState(),
        showStartCue: cue,
        onCellTap: (_, _) {},
        onCellDrag: (_, _) {},
      ),
    ),
  );
}

void main() {
  setUpTestEnvironment();

  group('start cue on the grid', () {
    testWidgets('pulses with motion allowed', (tester) async {
      await tester.pumpWidget(_grid(cue: true));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        tester.widget<PuzzleGrid>(find.byType(PuzzleGrid)).showStartCue,
        isTrue,
      );
      expect(tester.takeException(), isNull);
      expect(tester.binding.transientCallbackCount, greaterThan(0));
    });

    testWidgets('reduced motion: static ring, no controller ticking', (
      tester,
    ) async {
      await tester.pumpWidget(_grid(cue: true, reduceMotion: true));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        tester.widget<PuzzleGrid>(find.byType(PuzzleGrid)).showStartCue,
        isTrue,
      );
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('turning the cue off stops the pulse', (tester) async {
      await tester.pumpWidget(_grid(cue: true, reduceMotion: false));
      await tester.pumpWidget(_grid(cue: false, reduceMotion: true));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.binding.transientCallbackCount, 0);
    });

    for (final brightness in Brightness.values) {
      for (final mode in ColorblindMode.values) {
        test(
          'ring is at least 3:1 on the cell ($brightness, ${mode.name})',
          () {
            final p = GridPalette.forMode(mode, brightness: brightness);
            expect(
              contrastRatio(p.hint, p.cellBackground),
              greaterThanOrEqualTo(3.0),
            );
          },
        );
      }
    }
  });

  group('FirstPlayTooltip', () {
    testWidgets('shows the text, has a label and dismisses on tap', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      var dismissed = 0;
      await tester.pumpWidget(
        buildTestWidgetInScaffold(
          FirstPlayTooltip(onDismiss: () => dismissed++),
        ),
      );
      expect(find.text(AppStrings.firstPlayTooltip), findsOneWidget);
      expect(
        find.bySemanticsLabel(AppStrings.firstPlayTooltip),
        findsOneWidget,
      );
      await tester.tap(find.text(AppStrings.firstPlayTooltip));
      expect(dismissed, 1);
      handle.dispose();
    });

    for (final dark in [true, false]) {
      testWidgets('text contrast >= 4.5:1 (${dark ? 'dark' : 'light'})', (
        tester,
      ) async {
        await tester.pumpWidget(
          buildTestWidgetInScaffold(
            FirstPlayTooltip(onDismiss: () {}),
            theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
          ),
        );
        final p = dark ? AppPalette.dark : AppPalette.light;
        expect(
          contrastRatio(
            resolvedTextColor(tester, find.text(AppStrings.firstPlayTooltip)),
            p.elevated,
          ),
          greaterThanOrEqualTo(4.5),
        );
      });
    }

    testWidgets('no overflow at 200% text on 320x568', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 568),
            textScaler: TextScaler.linear(2),
          ),
          child: buildTestWidgetInScaffold(
            Padding(
              padding: const EdgeInsets.all(16),
              child: FirstPlayTooltip(onDismiss: () {}),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
