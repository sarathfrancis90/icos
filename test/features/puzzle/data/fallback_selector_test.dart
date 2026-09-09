import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icos/features/puzzle/data/fallback_selector.dart';
import 'package:icos/features/puzzle/domain/solver/puzzle_core.dart'
    show fnv1a32, weekdayDifficulty;

void main() {
  group('fnv1a32', () {
    test('known vectors', () {
      expect(fnv1a32(''), 0x811C9DC5);
      expect(fnv1a32('a'), 0xE40C292C);
      expect(fnv1a32('foobar'), 0xBF9CF968);
    });

    test('is stable and non-negative', () {
      expect(fnv1a32('2026-09-09'), fnv1a32('2026-09-09'));
      expect(fnv1a32('2026-09-09'), greaterThanOrEqualTo(0));
      expect(fnv1a32('2026-09-09'), isNot(fnv1a32('2026-09-10')));
    });
  });

  group('selectFallbackIndex', () {
    late List<Map<String, dynamic>> bundled;

    setUpAll(() {
      final file = File('assets/puzzles/fallback_puzzles.json');
      bundled = (jsonDecode(file.readAsStringSync()) as List<dynamic>)
          .cast<Map<String, dynamic>>();
    });

    test('is deterministic for a date', () {
      final a = selectFallbackIndex('2026-09-09', bundled);
      final b = selectFallbackIndex('2026-09-09', bundled);
      expect(a, b);
      expect(a, inInclusiveRange(0, bundled.length - 1));
    });

    test('picks a puzzle matching the weekday difficulty', () {
      // Every day of one week.
      for (var day = 7; day <= 13; day++) {
        final date = '2026-09-${day.toString().padLeft(2, '0')}';
        final index = selectFallbackIndex(date, bundled);
        expect(
          bundled[index]['difficulty'],
          weekdayDifficulty(date).name,
          reason: date,
        );
      }
    });

    test('falls back to hashing over the whole list when nothing matches', () {
      final list = [
        {'difficulty': 'nope'},
        {'difficulty': 'nope'},
        {'difficulty': 'nope'},
      ];
      final index = selectFallbackIndex('2026-09-09', list);
      expect(index, fnv1a32('2026-09-09') % 3);
    });

    test('returns -1 for an empty list', () {
      expect(selectFallbackIndex('2026-09-09', const []), -1);
    });

    test('breaks ties between same-difficulty candidates by hash', () {
      final list = [
        {'difficulty': 'easy', 'id': 'a'},
        {'difficulty': 'hard', 'id': 'b'},
        {'difficulty': 'easy', 'id': 'c'},
      ];
      // Monday → easy → candidates [0, 2].
      final index = selectFallbackIndex('2026-09-07', list);
      expect(index, [0, 2][fnv1a32('2026-09-07') % 2]);
    });
  });
}
