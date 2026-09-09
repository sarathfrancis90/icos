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

  group('weekStartOf', () {
    // 2026-09-07 is a Monday, 2026-09-13 a Sunday.
    test('Monday 00:00:00 UTC maps to itself', () {
      final monday = DateTime.utc(2026, 9, 7);
      expect(monday.weekday, DateTime.monday);
      expect(AppDateUtils.weekStartOf(monday), DateTime.utc(2026, 9, 7));
    });

    test('Sunday 23:59:59 UTC maps to the Monday six days earlier', () {
      final sunday = DateTime.utc(2026, 9, 13, 23, 59, 59);
      expect(sunday.weekday, DateTime.sunday);
      expect(AppDateUtils.weekStartOf(sunday), DateTime.utc(2026, 9, 7));
    });

    test('Monday 00:00:00 minus one second belongs to the previous week', () {
      final justBefore = DateTime.utc(2026, 9, 7).subtract(
        const Duration(seconds: 1),
      );
      expect(AppDateUtils.weekStartOf(justBefore), DateTime.utc(2026, 8, 31));
    });

    test('mid-week time is truncated to Monday midnight', () {
      final wednesday = DateTime.utc(2026, 9, 9, 15, 42, 7);
      final start = AppDateUtils.weekStartOf(wednesday);
      expect(start, DateTime.utc(2026, 9, 7));
      expect(start.isUtc, isTrue);
      expect(start.hour, 0);
    });

    test('local times are converted to UTC first', () {
      final local = DateTime.utc(2026, 9, 13, 23, 30).toLocal();
      expect(AppDateUtils.weekStartOf(local), DateTime.utc(2026, 9, 7));
    });

    test('crosses month and year boundaries', () {
      // 2027-01-01 is a Friday; its week starts Monday 2026-12-28.
      expect(
        AppDateUtils.weekStartOf(DateTime.utc(2027, 1, 1, 12)),
        DateTime.utc(2026, 12, 28),
      );
    });
  });

  group('dateNDaysAgo', () {
    final from = DateTime.utc(2026, 9, 9, 0, 0, 1);

    test('0 is the same day', () {
      expect(AppDateUtils.dateNDaysAgo(0, from: from), '2026-09-09');
    });

    test('1 is yesterday even one second after midnight UTC', () {
      expect(AppDateUtils.dateNDaysAgo(1, from: from), '2026-09-08');
    });

    test('negative values go forward', () {
      expect(AppDateUtils.dateNDaysAgo(-1, from: from), '2026-09-10');
    });

    test('crosses month boundaries', () {
      expect(
        AppDateUtils.dateNDaysAgo(1, from: DateTime.utc(2026, 3, 1)),
        '2026-02-28',
      );
    });

    test('crosses year boundaries', () {
      expect(
        AppDateUtils.dateNDaysAgo(1, from: DateTime.utc(2027, 1, 1)),
        '2026-12-31',
      );
    });

    test('recentDates excludes today and is newest first', () {
      final dates = AppDateUtils.recentDates(3, from: from);
      expect(dates, ['2026-09-08', '2026-09-07', '2026-09-06']);
    });
  });

  group('isTodayOrTomorrowUtc / daysAgo', () {
    final now = DateTime.utc(2026, 9, 9, 23, 59, 59);

    test('today and tomorrow are allowed, others are not', () {
      expect(AppDateUtils.isTodayOrTomorrowUtc('2026-09-09', now: now), isTrue);
      expect(AppDateUtils.isTodayOrTomorrowUtc('2026-09-10', now: now), isTrue);
      expect(AppDateUtils.isTodayOrTomorrowUtc('2026-09-08', now: now), isFalse);
      expect(AppDateUtils.isTodayOrTomorrowUtc('2026-09-11', now: now), isFalse);
    });

    test('daysAgo counts whole UTC days', () {
      expect(AppDateUtils.daysAgo('2026-09-09', now: now), 0);
      expect(AppDateUtils.daysAgo('2026-09-02', now: now), 7);
      expect(AppDateUtils.daysAgo('2026-09-01', now: now), 8);
    });

    test('weekdayOf uses UTC weekday', () {
      expect(AppDateUtils.weekdayOf('2026-09-07'), DateTime.monday);
      expect(AppDateUtils.weekdayOf('2026-09-13'), DateTime.sunday);
    });

    test('formatDateHuman', () {
      expect(AppDateUtils.formatDateHuman('2026-09-09'), 'Wed, 9 Sep');
    });
  });
}
