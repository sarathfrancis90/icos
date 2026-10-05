import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icos/core/constants/app_urls.dart';
import 'package:icos/shared/widgets/legal_consent_text.dart';

import '../../helpers/test_helpers.dart';

void main() {
  setUpTestEnvironment();

  Widget host(List<String> opened) => buildTestWidget(
    Scaffold(
      body: Center(
        child: LegalConsentText(
          onOpen: (url) async {
            opened.add(url);
            return true;
          },
        ),
      ),
    ),
  );

  testWidgets('renders the consent sentence with two links', (tester) async {
    await tester.pumpWidget(host([]));
    expect(find.textContaining('By continuing, you agree to our'),
        findsOneWidget);
    expect(find.text('Terms of Service'), findsOneWidget);
    expect(find.text('Privacy Policy'), findsOneWidget);
  });

  testWidgets('each link opens its own url', (tester) async {
    final opened = <String>[];
    await tester.pumpWidget(host(opened));
    await tester.tap(find.text('Terms of Service'));
    await tester.tap(find.text('Privacy Policy'));
    expect(opened, [kTermsUrl, kPrivacyPolicyUrl]);
  });

  testWidgets('links are exposed as semantic links with labels',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(host([]));
    for (final label in ['Terms of Service', 'Privacy Policy']) {
      final data = tester.getSemantics(find.bySemanticsLabel(label));
      expect(data.hasFlag(SemanticsFlag.isLink), isTrue, reason: label);
    }
    handle.dispose();
  });

  testWidgets('links meet the 44dp touch target', (tester) async {
    await tester.pumpWidget(host([]));
    for (final label in ['Terms of Service', 'Privacy Policy']) {
      final box = tester.getSize(
        find.ancestor(
          of: find.text(label),
          matching: find.byType(InkWell),
        ),
      );
      expect(box.height, greaterThanOrEqualTo(44), reason: label);
    }
  });

  testWidgets('does not overflow at 200% text on a 320x568 screen',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 568),
          textScaler: TextScaler.linear(2),
        ),
        child: host([]),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
