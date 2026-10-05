import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icos/core/constants/app_strings.dart';
import 'package:icos/features/puzzle/presentation/widgets/offline_puzzle_notice.dart';

import '../../../../helpers/test_helpers.dart';

void main() {
  setUpTestEnvironment();

  testWidgets('shows the practice message with a semantics label', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      buildTestWidgetInScaffold(const OfflinePuzzleNotice()),
    );

    expect(find.text(AppStrings.offlinePuzzleNotice), findsOneWidget);
    expect(
      AppStrings.offlinePuzzleNotice,
      "Offline puzzle. This one is just for practice and won't count toward "
      'your streak.',
    );
    expect(
      find.bySemanticsLabel(AppStrings.offlinePuzzleNotice),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('does not overflow at 200% text on a 320x568 screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 568),
          textScaler: TextScaler.linear(2),
        ),
        child: buildTestWidgetInScaffold(const OfflinePuzzleNotice()),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
