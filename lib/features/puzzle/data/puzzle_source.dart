import '../../../core/utils/date_utils.dart';

/// Where a puzzle comes from and how its result is handled.
///
/// * [DailyPuzzleSource] — today's puzzle; submitted to the server, counts
///   toward streaks.
/// * [ArchivePuzzleSource] — a past date; submitted to the server (marked
///   `is_archive`, never affects streaks).
/// * [PracticePuzzleSource] — generated locally; never submitted.
sealed class PuzzleSource {
  const PuzzleSource();

  const factory PuzzleSource.daily(String date) = DailyPuzzleSource;
  const factory PuzzleSource.archive(String date) = ArchivePuzzleSource;
  const factory PuzzleSource.practice({
    required int seed,
    required int size,
    required String difficulty,
  }) = PracticePuzzleSource;

  /// Daily when [date] is today (UTC), otherwise archive.
  factory PuzzleSource.forDate(String date) =>
      date == AppDateUtils.todayUtc()
          ? PuzzleSource.daily(date)
          : PuzzleSource.archive(date);

  /// ISO date for server-backed sources, `null` for practice.
  String? get date;

  /// Key used for local game-state persistence.
  String get storageKey;

  bool get submitsToServer;
  bool get isArchive => this is ArchivePuzzleSource;
  bool get isPractice => this is PracticePuzzleSource;
}

final class DailyPuzzleSource extends PuzzleSource {
  const DailyPuzzleSource(this.date);

  @override
  final String date;

  @override
  String get storageKey => date;

  @override
  bool get submitsToServer => true;

  @override
  bool operator ==(Object other) =>
      other is DailyPuzzleSource && other.date == date;

  @override
  int get hashCode => Object.hash('daily', date);

  @override
  String toString() => 'PuzzleSource.daily($date)';
}

final class ArchivePuzzleSource extends PuzzleSource {
  const ArchivePuzzleSource(this.date);

  @override
  final String date;

  @override
  String get storageKey => date;

  @override
  bool get submitsToServer => true;

  @override
  bool operator ==(Object other) =>
      other is ArchivePuzzleSource && other.date == date;

  @override
  int get hashCode => Object.hash('archive', date);

  @override
  String toString() => 'PuzzleSource.archive($date)';
}

final class PracticePuzzleSource extends PuzzleSource {
  const PracticePuzzleSource({
    required this.seed,
    required this.size,
    required this.difficulty,
  });

  final int seed;
  final int size;
  final String difficulty;

  @override
  String? get date => null;

  @override
  String get storageKey => 'practice_${size}_${difficulty}_$seed';

  @override
  bool get submitsToServer => false;

  @override
  bool operator ==(Object other) =>
      other is PracticePuzzleSource &&
      other.seed == seed &&
      other.size == size &&
      other.difficulty == difficulty;

  @override
  int get hashCode => Object.hash('practice', seed, size, difficulty);

  @override
  String toString() => 'PuzzleSource.practice($size, $difficulty, $seed)';
}
