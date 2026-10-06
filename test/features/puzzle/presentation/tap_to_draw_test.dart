import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icos/core/constants/app_strings.dart';
import 'package:icos/core/services/storage_service.dart';
import 'package:icos/features/profile/presentation/widgets/tap_to_draw_tile.dart';
import 'package:icos/features/puzzle/presentation/widgets/first_play_tooltip.dart';
import 'package:icos/features/puzzle/presentation/widgets/puzzle_grid.dart';
import 'package:icos/features/puzzle/providers/tap_to_draw_provider.dart';

import '../../../helpers/storage_test_helpers.dart';
import '../../../helpers/test_helpers.dart';

void main() {
  setUpTestEnvironment();

  late Directory dir;
  setUp(() async => dir = await initTestStorage());
  tearDown(() async => dir.delete(recursive: true));

  test('defaults off and persists device-level', () async {
    expect(StorageService.tapToDraw, isFalse);
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(tapToDrawProvider), isFalse);
    await c.read(tapToDrawProvider.notifier).set(true);
    expect(c.read(tapToDrawProvider), isTrue);
    expect(StorageService.tapToDraw, isTrue);
    final again = ProviderContainer();
    addTearDown(again.dispose);
    expect(again.read(tapToDrawProvider), isTrue);
  });

  testWidgets('settings tile toggles the mode', (tester) async {
    await tester.pumpWidget(
      buildTestWidgetInScaffold(const Material(child: TapToDrawTile())),
    );
    expect(find.text(AppStrings.tapToDrawTitle), findsOneWidget);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    expect(StorageService.tapToDraw, isTrue);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );
  });

  testWidgets('tooltip copy switches', (tester) async {
    for (final tap in [false, true]) {
      await tester.pumpWidget(
        buildTestWidgetInScaffold(
          FirstPlayTooltip(onDismiss: () {}, tapToDraw: tap),
        ),
      );
      expect(
        find.text(
          tap ? AppStrings.firstPlayTooltipTap : AppStrings.firstPlayTooltip,
        ),
        findsOneWidget,
      );
    }
    expect(
      AppStrings.firstPlayTooltipTap,
      'Tap the next cell to draw your path — start at 1',
    );
  });

  Widget grid({required bool tap, List<String>? log}) =>
      buildTestWidgetInScaffold(
        PuzzleGrid(
          gameState: createPlayingGameState(),
          tapToDraw: tap,
          onCellTap: (r, c) => log?.add('tap $r,$c'),
          onCellDrag: (r, c) => log?.add('drag $r,$c'),
        ),
      );

  testWidgets('cell semantics hints and mode announcement when on', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(grid(tap: true));
    expect(find.bySemanticsLabel(AppStrings.tapToDrawModeOn), findsOneWidget);
    final node = tester.widget<Semantics>(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'Row 1, Column 3, empty',
      ),
    );
    expect(node.properties.hint, AppStrings.tapToDrawAddHint);
    expect(AppStrings.tapToDrawAddHint, 'Double tap to add to path');
    expect(AppStrings.tapToDrawRemoveHint, 'Double tap to remove from path');
    handle.dispose();
  });

  testWidgets('no hints or announcement when off', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(grid(tap: false));
    expect(find.bySemanticsLabel(AppStrings.tapToDrawModeOn), findsNothing);
    final node = tester.widget<Semantics>(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'Row 1, Column 3, empty',
      ),
    );
    expect(node.properties.hint, isNull);
    handle.dispose();
  });

  testWidgets('drag still reaches the grid when tap to draw is on', (
    tester,
  ) async {
    final log = <String>[];
    await tester.pumpWidget(grid(tap: true, log: log));
    final box = find
        .descendant(
          of: find.byType(PuzzleGrid),
          matching: find.byType(CustomPaint),
        )
        .first;
    final cell = tester.getSize(box).width / 3;
    await tester.dragFrom(
      tester.getTopLeft(box) + Offset(cell / 2, cell / 2),
      Offset(cell, 0),
    );
    expect(log.any((e) => e.startsWith('drag')), isTrue);
  });
}
