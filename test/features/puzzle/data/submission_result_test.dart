import 'package:flutter_test/flutter_test.dart';
import 'package:icos/features/puzzle/data/puzzle_source.dart';
import 'package:icos/features/puzzle/data/submission_result.dart';

void main() {
  group('SubmissionResult', () {
    test('JSON round trip preserves every field', () {
      final original = SubmissionResult(
        date: '2026-09-09',
        status: SubmissionStatus.verified,
        timeSeconds: 61,
        hintsUsed: 2,
        undosUsed: 3,
        path: const [
          [0, 0],
          [0, 1],
        ],
        completedAt: DateTime.utc(2026, 9, 9, 10, 30),
        isArchive: true,
        streak: const StreakSnapshot(
          currentStreak: 4,
          longestStreak: 9,
          freezeCount: 1,
          lastSolveDate: '2026-09-09',
        ),
        rankHint: 12,
        reason: null,
      );

      final copy = SubmissionResult.fromJson(original.toJson());
      expect(copy.date, original.date);
      expect(copy.status, SubmissionStatus.verified);
      expect(copy.timeSeconds, 61);
      expect(copy.hintsUsed, 2);
      expect(copy.undosUsed, 3);
      expect(copy.path, original.path);
      expect(copy.completedAt, original.completedAt);
      expect(copy.isArchive, isTrue);
      expect(copy.streak?.currentStreak, 4);
      expect(copy.streak?.longestStreak, 9);
      expect(copy.streak?.freezeCount, 1);
      expect(copy.streak?.lastSolveDate, '2026-09-09');
      expect(copy.rankHint, 12);
    });

    test('unknown status parses as pending', () {
      expect(SubmissionStatus.parse('bogus'), SubmissionStatus.pending);
      expect(SubmissionStatus.parse(null), SubmissionStatus.pending);
    });

    test('status helpers', () {
      SubmissionResult make(SubmissionStatus s) => SubmissionResult(
            date: 'd',
            status: s,
            timeSeconds: 1,
            hintsUsed: 0,
            undosUsed: 0,
            path: const [],
            completedAt: DateTime.utc(2026),
          );
      expect(make(SubmissionStatus.verified).isAccepted, isTrue);
      expect(make(SubmissionStatus.unverified).isAccepted, isTrue);
      expect(make(SubmissionStatus.rejected).isRejected, isTrue);
      expect(make(SubmissionStatus.pending).isPending, isTrue);
      expect(make(SubmissionStatus.localOnly).isAccepted, isFalse);
    });
  });

  group('PuzzleSource', () {
    test('value equality and storage keys', () {
      expect(
        const PuzzleSource.daily('2026-09-09'),
        const PuzzleSource.daily('2026-09-09'),
      );
      expect(
        const PuzzleSource.daily('2026-09-09'),
        isNot(const PuzzleSource.archive('2026-09-09')),
      );
      expect(const PuzzleSource.daily('2026-09-09').storageKey, '2026-09-09');
      const practice = PuzzleSource.practice(seed: 7, size: 6, difficulty: 'hard');
      expect(practice, const PuzzleSource.practice(seed: 7, size: 6, difficulty: 'hard'));
      expect(practice.storageKey, 'practice_6_hard_7');
      expect(practice.submitsToServer, isFalse);
      expect(practice.date, isNull);
      expect(const PuzzleSource.archive('2026-09-01').isArchive, isTrue);
    });
  });
}
