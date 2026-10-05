import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icos/features/puzzle/presentation/widgets/puzzle_grid.dart';
import 'package:icos/shared/widgets/content_width_limit.dart';

import '../../helpers/test_helpers.dart';

void main() {
  setUpTestEnvironment();

  Future<void> useScreen(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  const ipad = Size(834, 1194);
  const phone = Size(393, 852);

  Widget grid() => buildTestWidgetInScaffold(
    PuzzleGrid(
      gameState: createPlayingGameState(),
      onCellTap: (_, _) {},
      onCellDrag: (_, _) {},
    ),
  );

  testWidgets('content is at most 600dp wide and centred on an iPad', (
    tester,
  ) async {
    await useScreen(tester, ipad);
    await tester.pumpWidget(
      MaterialApp(
        home: ContentWidthLimit(child: Container(key: const Key('c'))),
      ),
    );
    final rect = tester.getRect(find.byKey(const Key('c')));
    expect(rect.width, 600);
    expect(rect.center.dx, ipad.width / 2);
  });

  testWidgets('content is untouched on a phone', (tester) async {
    await useScreen(tester, phone);
    await tester.pumpWidget(
      MaterialApp(
        home: ContentWidthLimit(child: Container(key: const Key('c'))),
      ),
    );
    expect(tester.getSize(find.byKey(const Key('c'))).width, phone.width);
  });

  testWidgets('the puzzle grid is at most 500dp wide on an iPad', (
    tester,
  ) async {
    await useScreen(tester, ipad);
    await tester.pumpWidget(grid());
    final size = tester.getSize(find.byType(PuzzleGrid));
    // The grid's own square, not the padded slot it sits in.
    final square = tester.getSize(
      find
          .descendant(
            of: find.byType(PuzzleGrid),
            matching: find.byWidgetPredicate(
              (w) => w is SizedBox && w.width != null && w.width == w.height,
            ),
          )
          .first,
    );
    expect(square.width, lessThanOrEqualTo(500));
    expect(square.width, greaterThan(400));
    expect(size.width, greaterThan(0));
  });

  testWidgets('the puzzle grid still fills a phone', (tester) async {
    await useScreen(tester, phone);
    await tester.pumpWidget(grid());
    final square = tester.getSize(
      find
          .descendant(
            of: find.byType(PuzzleGrid),
            matching: find.byWidgetPredicate(
              (w) => w is SizedBox && w.width != null && w.width == w.height,
            ),
          )
          .first,
    );
    expect(square.width, phone.width - 48);
  });
}
