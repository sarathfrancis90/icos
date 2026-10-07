import 'package:flutter_test/flutter_test.dart';
import 'package:icos/core/utils/date_utils.dart';
import 'package:icos/core/utils/utc_day_rollover.dart';

void main() {
  group('AppDateUtils.untilNextRollover', () {
    test('from mid-day, waits until 00:00:01 UTC the next day', () {
      expect(
        AppDateUtils.untilNextRollover(now: DateTime.utc(2026, 10, 7, 23)),
        const Duration(hours: 1, seconds: 1),
      );
    });

    test('just before 00:00:01 waits for today\'s 00:00:01', () {
      expect(
        AppDateUtils.untilNextRollover(now: DateTime.utc(2026, 10, 8)),
        const Duration(seconds: 1),
      );
    });

    test('exactly at 00:00:01 waits a full day', () {
      expect(
        AppDateUtils.untilNextRollover(
          now: DateTime.utc(2026, 10, 8, 0, 0, 1),
        ),
        const Duration(days: 1),
      );
    });

    test('a local time is read in UTC', () {
      final now = DateTime.utc(2026, 10, 7, 12).toLocal();
      expect(
        AppDateUtils.untilNextRollover(now: now),
        const Duration(hours: 12, seconds: 1),
      );
    });

    test('defaults to the app clock', () {
      final real = AppDateUtils.clock;
      addTearDown(() => AppDateUtils.clock = real);
      AppDateUtils.clock = () => DateTime.utc(2026, 12, 31, 22);
      expect(
        AppDateUtils.untilNextRollover(),
        const Duration(hours: 2, seconds: 1),
      );
    });
  });

  group('UtcDayRollover', () {
    late DateTime now;
    late DateTime Function() realClock;

    setUp(() {
      realClock = AppDateUtils.clock;
      now = DateTime.utc(2026, 10, 7, 23, 59);
      AppDateUtils.clock = () => now;
    });
    tearDown(() => AppDateUtils.clock = realClock);

    testWidgets('fires once the UTC day changes while running, and re-arms', (
      tester,
    ) async {
      final days = <String>[];
      final rollover = UtcDayRollover(onNewDay: days.add)..start();

      now = now.add(const Duration(seconds: 30));
      await tester.pump(const Duration(seconds: 30));
      expect(days, isEmpty);

      now = DateTime.utc(2026, 10, 8, 0, 0, 1);
      await tester.pump(const Duration(seconds: 31));
      expect(days, ['2026-10-08']);

      now = DateTime.utc(2026, 10, 9, 0, 0, 1);
      await tester.pump(const Duration(days: 1));
      expect(days, ['2026-10-08', '2026-10-09']);
      rollover.dispose();
    });

    testWidgets('check() reports a change only once per day', (tester) async {
      final days = <String>[];
      final rollover = UtcDayRollover(onNewDay: days.add);
      addTearDown(rollover.dispose);

      expect(rollover.check(), isFalse);
      now = DateTime.utc(2026, 10, 8, 9);
      expect(rollover.check(), isTrue);
      expect(rollover.check(), isFalse);
      expect(days, ['2026-10-08']);
    });

    testWidgets('dispose cancels the pending timer', (tester) async {
      final days = <String>[];
      final rollover = UtcDayRollover(onNewDay: days.add)..start();
      rollover.dispose();
      now = DateTime.utc(2026, 10, 8, 0, 0, 1);
      await tester.pump(const Duration(minutes: 2));
      expect(days, isEmpty);
    });

    testWidgets('start() again replaces the pending timer', (tester) async {
      final days = <String>[];
      final rollover = UtcDayRollover(onNewDay: days.add)..start();
      rollover.start();
      now = DateTime.utc(2026, 10, 8, 0, 0, 1);
      await tester.pump(const Duration(minutes: 2));
      expect(days, ['2026-10-08']);
      rollover.dispose();
    });
  
    testWidgets('onSettled runs once, 11 minutes after the rollover', (
      tester,
    ) async {
      final days = <String>[];
      var settled = 0;
      final rollover = UtcDayRollover(
        onNewDay: days.add,
        onSettled: () => settled++,
      )..start();

      now = DateTime.utc(2026, 10, 8, 0, 0, 1);
      await tester.pump(const Duration(seconds: 61));
      expect(days, ['2026-10-08']);
      expect(settled, 0);

      now = DateTime.utc(2026, 10, 8, 0, 10, 59);
      await tester.pump(const Duration(minutes: 10, seconds: 58));
      expect(settled, 0);
      now = DateTime.utc(2026, 10, 8, 0, 11, 1);
      await tester.pump(const Duration(seconds: 2));
      expect(settled, 1);
      rollover.dispose();
    });

    testWidgets('a day change noticed late (resume) does not wait to settle', (
      tester,
    ) async {
      var settled = 0;
      final rollover = UtcDayRollover(
        onNewDay: (_) {},
        onSettled: () => settled++,
      );
      now = DateTime.utc(2026, 10, 8, 9);
      expect(rollover.check(), isTrue);
      await tester.pump(const Duration(minutes: 20));
      expect(settled, 0);
      rollover.dispose();
    });

    testWidgets('resume shortly after midnight settles at 00:11 UTC', (
      tester,
    ) async {
      var settled = 0;
      final rollover = UtcDayRollover(
        onNewDay: (_) {},
        onSettled: () => settled++,
      );
      now = DateTime.utc(2026, 10, 8, 0, 6);
      expect(rollover.check(), isTrue);
      await tester.pump(const Duration(minutes: 4, seconds: 59));
      expect(settled, 0);
      await tester.pump(const Duration(seconds: 2));
      expect(settled, 1);
      rollover.dispose();
    });

    testWidgets('dispose cancels a pending settle', (tester) async {
      var settled = 0;
      final rollover = UtcDayRollover(
        onNewDay: (_) {},
        onSettled: () => settled++,
      );
      now = DateTime.utc(2026, 10, 8, 0, 0, 1);
      rollover
        ..check()
        ..dispose();
      await tester.pump(const Duration(minutes: 15));
      expect(settled, 0);
    });
  });
}
