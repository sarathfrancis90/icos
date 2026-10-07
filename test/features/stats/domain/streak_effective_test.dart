import 'package:flutter_test/flutter_test.dart';
import 'package:icos/features/stats/domain/models/streak.dart';

void main() {
  final today = DateTime.utc(2026, 10, 7, 15);

  Streak streak({String? solve, String? freeze, int current = 5}) => Streak(
    userId: 'u',
    currentStreak: current,
    longestStreak: 9,
    freezeCount: 1,
    lastSolveDate: solve,
    lastFreezeUsedAt: freeze,
  );

  group('effectiveCurrentStreak', () {
    test('solved today keeps the streak', () {
      expect(
        streak(solve: '2026-10-07').effectiveCurrentStreak(todayUtc: today),
        5,
      );
    });

    test('solved yesterday keeps the streak (today still open)', () {
      expect(
        streak(solve: '2026-10-06').effectiveCurrentStreak(todayUtc: today),
        5,
      );
    });

    test('last solve two days ago is a broken streak', () {
      expect(
        streak(solve: '2026-10-05').effectiveCurrentStreak(todayUtc: today),
        0,
      );
    });

    test('a freeze used yesterday keeps an older solve alive', () {
      expect(
        streak(
          solve: '2026-10-05',
          freeze: '2026-10-06',
        ).effectiveCurrentStreak(todayUtc: today),
        5,
      );
    });

    test('an old freeze does not keep the streak alive', () {
      expect(
        streak(
          solve: '2026-10-03',
          freeze: '2026-10-04',
        ).effectiveCurrentStreak(todayUtc: today),
        0,
      );
    });

    test('no solve and no freeze is 0', () {
      expect(streak().effectiveCurrentStreak(todayUtc: today), 0);
    });

    test('a timestamp-shaped date is read by its day', () {
      expect(
        streak(
          solve: '2026-10-06T00:00:00+00:00',
        ).effectiveCurrentStreak(todayUtc: today),
        5,
      );
    });

    test('midnight UTC boundary: yesterday ends the moment today starts', () {
      final justAfterMidnight = DateTime.utc(2026, 10, 8, 0, 0, 1);
      expect(
        streak(
          solve: '2026-10-06',
        ).effectiveCurrentStreak(todayUtc: justAfterMidnight),
        0,
      );
    });

    test('a local DateTime is converted to UTC', () {
      expect(
        streak(
          solve: '2026-10-06',
        ).effectiveCurrentStreak(todayUtc: today.toLocal()),
        5,
      );
    });

    test('a zero streak stays zero', () {
      expect(
        streak(
          solve: '2026-10-07',
          current: 0,
        ).effectiveCurrentStreak(todayUtc: today),
        0,
      );
    });
  });
}
