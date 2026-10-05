import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

  Finder sentence() => find.byWidgetPredicate(
    (w) => w is RichText && w.text.toPlainText().startsWith('By continuing'),
  );

  RenderParagraph paragraph(WidgetTester tester) =>
      tester.renderObject<RenderParagraph>(sentence());

  /// Screen rectangle of the first line box of [label] within the sentence.
  Rect rectOf(WidgetTester tester, String label) {
    final p = paragraph(tester);
    final start = p.text.toPlainText().indexOf(label);
    final box = p
        .getBoxesForSelection(
          TextSelection(baseOffset: start, extentOffset: start + label.length),
        )
        .first;
    return box.toRect().shift(p.localToGlobal(Offset.zero));
  }

  const terms = 'Terms of Service';
  const privacy = 'Privacy Policy';

  testWidgets('renders the consent sentence with two links', (tester) async {
    await tester.pumpWidget(host([]));
    expect(
      find.text(
        'By continuing, you agree to our Terms of Service and Privacy Policy.',
        findRichText: true,
      ),
      findsOneWidget,
    );
  });

  testWidgets('each link opens its own url', (tester) async {
    final opened = <String>[];
    await tester.pumpWidget(host(opened));
    await tester.tapAt(rectOf(tester, terms).center);
    await tester.tapAt(rectOf(tester, privacy).center);
    await tester.pump(const Duration(seconds: 1));
    expect(opened, [kTermsUrl, kPrivacyPolicyUrl]);
  });

  testWidgets('links are exposed as semantic links with labels', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(host([]));
    for (final label in [terms, privacy]) {
      final data = find.semantics.byLabel(label).evaluate().single;
      expect(data.flagsCollection.isLink, isTrue, reason: label);
      expect(
        data.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
        reason: label,
      );
    }
    handle.dispose();
  });

  testWidgets('a link keeps its text height but is tappable within 44dp', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final opened = <String>[];
    await tester.pumpWidget(host(opened));

    for (final entry in {
      terms: kTermsUrl,
      privacy: kPrivacyPolicyUrl,
    }.entries) {
      final rect = rectOf(tester, entry.key);
      // The line is as tall as its text: nothing was stretched to 44dp.
      expect(rect.height, lessThan(30), reason: entry.key);
      // A tap 20dp above or below the link's centre (inside a 44dp target)
      // opens it...
      for (final dy in [-20.0, 20.0]) {
        opened.clear();
        await tester.tapAt(rect.center + Offset(0, dy));
        await tester.pump(const Duration(seconds: 1));
        expect(opened, [entry.value], reason: '${entry.key} dy=$dy');
      }
      // ...one 30dp away does not.
      opened.clear();
      await tester.tapAt(rect.center + const Offset(0, 40));
      await tester.pump(const Duration(seconds: 1));
      expect(opened, isEmpty, reason: '${entry.key} dy=40');
    }
  });

  testWidgets('a tap on a link opens it exactly once', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final opened = <String>[];
    await tester.pumpWidget(host(opened));
    await tester.tapAt(rectOf(tester, terms).center);
    await tester.pump(const Duration(seconds: 1));
    expect(opened, [kTermsUrl]);
  });

  testWidgets('reads as one sentence: the full stop stays on the last link\'s '
      'line, never alone (393 wide, normal text)', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host([]));

    final p = paragraph(tester);
    final text = p.text.toPlainText();
    expect(text.endsWith('Privacy Policy.'), isTrue);

    TextBox lastBoxOf(int start, int end) => p
        .getBoxesForSelection(
          TextSelection(baseOffset: start, extentOffset: end),
        )
        .last;

    final stop = lastBoxOf(text.length - 1, text.length);
    final y = lastBoxOf(text.length - 2, text.length - 1);
    expect(stop.top, y.top, reason: 'the "." is on the same line as the "y"');
    expect(stop.left, greaterThanOrEqualTo(y.right - 0.5));

    // No rendered line is a bare "." (or anything that narrow).
    final lines = <double, double>{};
    for (final box in p.getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: text.length),
    )) {
      lines[box.top] = (lines[box.top] ?? 0) + box.right - box.left;
    }
    expect(lines.length, greaterThanOrEqualTo(2));
    for (final width in lines.values) {
      expect(width, greaterThan(20), reason: 'a lone "." would be ~4dp');
    }
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
        child: host([]),
      ),
    );
    expect(
      MediaQuery.textScalerOf(
        tester.element(find.byType(LegalConsentText)),
      ).scale(10),
      20,
      reason: 'the 2.0 text scale must reach the widget under test',
    );
    expect(tester.takeException(), isNull);
  });
}
