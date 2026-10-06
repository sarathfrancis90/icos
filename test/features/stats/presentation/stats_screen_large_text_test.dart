import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icos/core/theme/app_theme.dart';
import 'package:icos/features/practice/providers/practice_provider.dart';
import 'package:icos/features/stats/presentation/stats_screen.dart';
import 'package:icos/features/stats/providers/stats_provider.dart';

import '../../../helpers/test_helpers.dart';

class _EmptyPracticeStats extends PracticeStatsNotifier {
  @override
  PracticeStats build() => const PracticeStats();
}

void main() {
  // The default test font is a fixed-width box font; the app uses Inter.
  setUpAll(() async {
    final loader = FontLoader('Inter');
    for (final weight in ['Regular', 'Bold']) {
      loader.addFont(
        Future.value(
          ByteData.sublistView(
            File('assets/google_fonts/Inter-$weight.ttf').readAsBytesSync(),
          ),
        ),
      );
    }
    await loader.load();
  });

  const overview = StatsOverview(
    currentStreak: 4,
    longestStreak: 9,
    totalSolved: 12,
    averageTimeSeconds: 95,
    freezeCount: 1,
    lastFreezeUsedAt: null,
  );

  Future<void> pumpAt(WidgetTester tester, Size size, double scale) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final theme = AppTheme.darkTheme.copyWith(
      textTheme: AppTheme.darkTheme.textTheme.apply(fontFamily: 'Inter'),
    );
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
        child: buildTestWidget(
          const Scaffold(body: StatsScreen()),
          theme: theme,
          overrides: [
            statsOverviewProvider.overrideWith((ref) async => overview),
            solveHistoryProvider.overrideWith((ref) async => []),
            practiceStatsNotifierProvider.overrideWith(_EmptyPracticeStats.new),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  void expectNoMidWordBreaks(WidgetTester tester, String label) {
    final paragraph =
        tester.renderObject(find.text(label).first) as RenderParagraph;
    var start = 0;
    for (final word in label.split(' ')) {
      final boxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: start + word.length),
      );
      expect(
        boxes.map((b) => b.top.round()).toSet().length,
        1,
        reason: '"$word" in "$label" is split across lines',
      );
      start += word.length + 1;
    }
  }

  for (final size in const [Size(320, 568), Size(393, 852)]) {
    testWidgets('two-up stat labels keep whole words at 200% on '
        '${size.width.toInt()}x${size.height.toInt()}', (tester) async {
      await pumpAt(tester, size, 2);

      for (final label in const [
        'Current Streak',
        'Longest Streak',
        'Puzzles Solved',
        'Average Time',
      ]) {
        await tester.scrollUntilVisible(
          find.text(label),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expectNoMidWordBreaks(tester, label);
      }

      // Stacked at 200%: the second card sits below the first.
      final solved = tester.getRect(find.text('Puzzles Solved'));
      final average = tester.getRect(find.text('Average Time'));
      expect(average.top, greaterThan(solved.bottom));
    });
  }
}
