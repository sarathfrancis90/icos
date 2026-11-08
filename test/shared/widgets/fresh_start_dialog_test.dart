import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icos/core/constants/app_strings.dart';
import 'package:icos/shared/widgets/fresh_start_dialog.dart';

void main() {
  testWidgets('FreshStartDialog shows the exact copy and dismisses with OK',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showFreshStartDialog(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Icos has moved to a new home'), findsOneWidget);
    expect(
      find.text(
        'Progress and groups start fresh in this version; your streak '
        'begins again today.',
      ),
      findsOneWidget,
    );
    expect(AppStrings.freshStartTitle, 'Icos has moved to a new home');
    expect(find.bySemanticsLabel(AppStrings.ok), findsOneWidget);

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.byType(FreshStartDialog), findsNothing);
    semantics.dispose();
  });
}
