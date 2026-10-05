import 'package:flutter_test/flutter_test.dart';
import 'package:icos/core/services/streak_reminder_schedule.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() {
  setUpAll(tzdata.initializeTimeZones);

  String? fire(String zone, DateTime nowUtc) {
    final t = streakReminderFireTime(
      nowUtc: nowUtc,
      location: tz.getLocation(zone),
    );
    if (t == null) return null;
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-'
        '${t.day.toString().padLeft(2, '0')} $h:$m';
  }

  // Early in the UTC day so nothing is "already past".
  final morning = DateTime.utc(2026, 1, 15, 6);

  group('streakReminderFireTime (winter, 4h before 00:00 UTC)', () {
    test('UTC-8 -> 12:00 same local day', () {
      expect(fire('America/Los_Angeles', morning), '2026-01-15 12:00');
    });
    test('UTC-5 -> 15:00', () {
      expect(fire('America/New_York', morning), '2026-01-15 15:00');
    });
    test('UTC+0 -> 20:00', () {
      expect(fire('UTC', morning), '2026-01-15 20:00');
    });
    test('UTC+1 -> 21:00', () {
      expect(
        fire('Europe/London', DateTime.utc(2026, 1, 15, 6)),
        '2026-01-15 20:00',
      );
      expect(fire('Europe/Paris', morning), '2026-01-15 21:00');
    });
    test('UTC+13 -> 09:00 next local day (not quiet)', () {
      expect(
        fire('Pacific/Auckland', DateTime.utc(2026, 1, 15, 6)),
        '2026-01-16 09:00',
      );
    });
  });

  group('quiet hours shift to 21:30 the evening before the deadline', () {
    test('UTC+5:30 (ideal 01:30)', () {
      expect(fire('Asia/Kolkata', morning), '2026-01-15 21:30');
    });
    test('UTC+9 (ideal 05:00)', () {
      expect(fire('Asia/Tokyo', morning), '2026-01-15 21:30');
    });
    test('UTC+3 (ideal 23:00) moves earlier to 21:30', () {
      expect(fire('Europe/Moscow', morning), '2026-01-15 21:30');
    });
    test('boundary: exactly 08:00 local is allowed, 22:00 is quiet', () {
      // UTC+12 -> ideal 08:00 local.
      expect(fire('Etc/GMT-12', morning), '2026-01-16 08:00');
      // UTC+2 -> ideal 22:00 local -> shifted.
      expect(fire('Etc/GMT-2', morning), '2026-01-15 21:30');
    });
  });

  group('already past', () {
    test('after the ideal time (UTC) there is no reminder', () {
      expect(fire('UTC', DateTime.utc(2026, 1, 15, 20)), isNull);
      expect(fire('UTC', DateTime.utc(2026, 1, 15, 22, 30)), isNull);
    });
    test('quiet-hours shift already past -> skipped', () {
      // 17:00 UTC = 22:30 IST; the 21:30 IST slot has gone, 01:30 is quiet.
      expect(fire('Asia/Kolkata', DateTime.utc(2026, 1, 15, 17)), isNull);
    });
    test('still ahead later the same UTC day -> fires', () {
      expect(
        fire('America/Los_Angeles', DateTime.utc(2026, 1, 15, 19)),
        '2026-01-15 12:00',
      );
      expect(
        fire('America/Los_Angeles', DateTime.utc(2026, 1, 15, 20)),
        isNull,
      );
    });
  });

  group('DST', () {
    test('US spring-forward day (2026-03-08)', () {
      // Deadline 2026-03-09 00:00Z = 20:00 EDT -> 16:00 EDT.
      expect(
        fire('America/New_York', DateTime.utc(2026, 3, 8, 12)),
        '2026-03-08 16:00',
      );
    });
    test('US fall-back day (2026-11-01)', () {
      // Deadline 2026-11-02 00:00Z = 19:00 EST -> 15:00 EST.
      expect(
        fire('America/New_York', DateTime.utc(2026, 11, 1, 12)),
        '2026-11-01 15:00',
      );
    });
    test('London summer time moves with the clock', () {
      expect(
        fire('Europe/London', DateTime.utc(2026, 7, 15, 6)),
        '2026-07-15 21:00',
      );
    });
    test('Auckland summer (UTC+13) in January vs winter (UTC+12)', () {
      expect(
        fire('Pacific/Auckland', DateTime.utc(2026, 7, 15, 6)),
        '2026-07-16 08:00',
      );
    });
  });

  group('copy', () {
    test('hours left is floored, at least 1, singular/plural', () {
      final deadline = DateTime.utc(2026, 1, 16);
      expect(
        streakReminderHoursLeft(DateTime.utc(2026, 1, 15, 20), deadline),
        4,
      );
      expect(
        streakReminderHoursLeft(DateTime.utc(2026, 1, 15, 12, 30), deadline),
        11,
      );
      expect(
        streakReminderHoursLeft(DateTime.utc(2026, 1, 15, 23, 40), deadline),
        1,
      );
      expect(streakReminderBody(1), "Today's puzzle closes in 1 hour.");
      expect(streakReminderBody(4), "Today's puzzle closes in 4 hours.");
    });
    test('deadline is the next 00:00 UTC', () {
      expect(
        streakDeadlineUtc(DateTime.utc(2026, 1, 15, 23, 59)),
        DateTime.utc(2026, 1, 16),
      );
      expect(
        streakDeadlineUtc(DateTime.utc(2026, 1, 16)),
        DateTime.utc(2026, 1, 17),
      );
    });
  });
}
