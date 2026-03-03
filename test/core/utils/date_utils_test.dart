import 'package:flutter_test/flutter_test.dart';
import 'package:icos/core/utils/date_utils.dart';

void main() {
  group('formatTime', () {
    test('formats 0 seconds as 00:00', () {
      expect(AppDateUtils.formatTime(0), '00:00');
    });

    test('formats seconds under a minute with leading zeros', () {
      expect(AppDateUtils.formatTime(5), '00:05');
      expect(AppDateUtils.formatTime(9), '00:09');
      expect(AppDateUtils.formatTime(59), '00:59');
    });

    test('formats exact minutes correctly', () {
      expect(AppDateUtils.formatTime(60), '01:00');
      expect(AppDateUtils.formatTime(120), '02:00');
      expect(AppDateUtils.formatTime(600), '10:00');
    });

    test('formats minutes and seconds correctly', () {
      expect(AppDateUtils.formatTime(61), '01:01');
      expect(AppDateUtils.formatTime(90), '01:30');
      expect(AppDateUtils.formatTime(125), '02:05');
      expect(AppDateUtils.formatTime(3661), '61:01');
    });

    test('formats large values correctly', () {
      expect(AppDateUtils.formatTime(3600), '60:00');
      expect(AppDateUtils.formatTime(5999), '99:59');
    });
  });

  group('formatTimeHuman', () {
    test('formats seconds under 60 with s suffix', () {
      expect(AppDateUtils.formatTimeHuman(0), '0s');
      expect(AppDateUtils.formatTimeHuman(1), '1s');
      expect(AppDateUtils.formatTimeHuman(30), '30s');
      expect(AppDateUtils.formatTimeHuman(59), '59s');
    });

    test('formats exact minutes with m suffix only', () {
      expect(AppDateUtils.formatTimeHuman(60), '1m');
      expect(AppDateUtils.formatTimeHuman(120), '2m');
      expect(AppDateUtils.formatTimeHuman(300), '5m');
    });

    test('formats minutes and seconds with m and s suffixes', () {
      expect(AppDateUtils.formatTimeHuman(61), '1m 1s');
      expect(AppDateUtils.formatTimeHuman(90), '1m 30s');
      expect(AppDateUtils.formatTimeHuman(125), '2m 5s');
    });

    test('formats large values correctly', () {
      expect(AppDateUtils.formatTimeHuman(3661), '61m 1s');
      expect(AppDateUtils.formatTimeHuman(3600), '60m');
    });
  });

  group('todayUtc', () {
    test('returns string in YYYY-MM-DD format', () {
      final result = AppDateUtils.todayUtc();
      // Verify the format matches YYYY-MM-DD
      expect(result, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
    });

    test('returns a parseable date string', () {
      final result = AppDateUtils.todayUtc();
      // Should not throw
      final parsed = DateTime.parse(result);
      expect(parsed, isA<DateTime>());
    });

    test('returns today UTC date', () {
      final result = AppDateUtils.todayUtc();
      final now = DateTime.now().toUtc();
      final expected =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      expect(result, expected);
    });
  });

  group('formatDate', () {
    test('formats date correctly', () {
      final date = DateTime(2026, 3, 3);
      expect(AppDateUtils.formatDate(date), '2026-03-03');
    });

    test('pads single-digit month and day', () {
      final date = DateTime(2026, 1, 5);
      expect(AppDateUtils.formatDate(date), '2026-01-05');
    });

    test('handles double-digit month and day', () {
      final date = DateTime(2026, 12, 25);
      expect(AppDateUtils.formatDate(date), '2026-12-25');
    });

    test('handles year with fewer than 4 digits', () {
      // Year 1 should be padded to 0001
      final date = DateTime(1, 1, 1);
      expect(AppDateUtils.formatDate(date), '0001-01-01');
    });
  });

  group('parseDate', () {
    test('parses YYYY-MM-DD string into DateTime', () {
      final result = AppDateUtils.parseDate('2026-03-03');
      expect(result.year, 2026);
      expect(result.month, 3);
      expect(result.day, 3);
    });

    test('roundtrips with formatDate', () {
      final original = DateTime(2026, 7, 15);
      final formatted = AppDateUtils.formatDate(original);
      final parsed = AppDateUtils.parseDate(formatted);
      expect(parsed.year, original.year);
      expect(parsed.month, original.month);
      expect(parsed.day, original.day);
    });
  });

  group('tomorrowUtc', () {
    test('returns string in YYYY-MM-DD format', () {
      final result = AppDateUtils.tomorrowUtc();
      expect(result, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
    });

    test('returns tomorrow UTC date', () {
      final result = AppDateUtils.tomorrowUtc();
      final tomorrow = DateTime.now().toUtc().add(const Duration(days: 1));
      final expected =
          '${tomorrow.year.toString().padLeft(4, '0')}-${tomorrow.month.toString().padLeft(2, '0')}-${tomorrow.day.toString().padLeft(2, '0')}';
      expect(result, expected);
    });
  });

  group('dayOfWeek', () {
    test('returns a value between 1 and 7', () {
      final result = AppDateUtils.dayOfWeek();
      expect(result, greaterThanOrEqualTo(1));
      expect(result, lessThanOrEqualTo(7));
    });

    test('matches current UTC weekday', () {
      final expected = DateTime.now().toUtc().weekday;
      expect(AppDateUtils.dayOfWeek(), expected);
    });
  });

  group('weekStart', () {
    test('returns a Monday', () {
      final result = AppDateUtils.weekStart();
      expect(result.weekday, DateTime.monday);
    });

    test('returns a UTC DateTime', () {
      final result = AppDateUtils.weekStart();
      expect(result.isUtc, isTrue);
    });

    test('returns midnight (00:00:00)', () {
      final result = AppDateUtils.weekStart();
      expect(result.hour, 0);
      expect(result.minute, 0);
      expect(result.second, 0);
    });

    test('returns Monday of current week', () {
      final now = DateTime.now().toUtc();
      final expectedMonday = now.subtract(Duration(days: now.weekday - 1));
      final result = AppDateUtils.weekStart();
      expect(result.year, expectedMonday.year);
      expect(result.month, expectedMonday.month);
      expect(result.day, expectedMonday.day);
    });

    test('returns same or earlier date than today', () {
      final now = DateTime.now().toUtc();
      final result = AppDateUtils.weekStart();
      // weekStart should be <= now
      expect(result.isBefore(now) || result.isAtSameMomentAs(now), isTrue);
    });
  });
}
