import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icos/core/constants/app_urls.dart';
import 'package:icos/features/profile/presentation/widgets/contact_support_tile.dart';

import '../../../helpers/test_helpers.dart';

void main() {
  setUpTestEnvironment();

  testWidgets('renders a Contact support row that opens a mailto', (
    tester,
  ) async {
    final opened = <String>[];
    await tester.pumpWidget(
      buildTestWidget(
        Scaffold(
          body: ContactSupportTile(
            onOpen: (url) async {
              opened.add(url);
              return true;
            },
          ),
        ),
      ),
    );

    final handle = tester.ensureSemantics();
    expect(find.text('Contact support'), findsOneWidget);
    expect(find.text(kSupportEmail), findsOneWidget);
    expect(find.bySemanticsLabel('Contact support by email'), findsOneWidget);
    handle.dispose();
    await tester.tap(find.text('Contact support'));
    expect(opened.single, startsWith('mailto:$kSupportEmail'));
  });

  testWidgets('shows in the About dialog', (tester) async {
    await tester.pumpWidget(
      buildTestWidget(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showAboutDialog(
              context: context,
              applicationName: 'Icos',
              children: const [ContactSupportTile()],
            ),
            child: const Text('about'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('about'));
    await tester.pumpAndSettle();
    expect(find.text('Contact support'), findsOneWidget);
  });
}
