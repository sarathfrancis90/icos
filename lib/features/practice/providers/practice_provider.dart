import 'dart:isolate';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/services/storage_service.dart';
import '../../puzzle/data/puzzle_source.dart';
import '../../puzzle/domain/models/puzzle.dart';
import '../../puzzle/domain/solver/puzzle_core.dart';

part 'practice_provider.g.dart';

/// Grid sizes offered in practice mode.
const practiceSizes = [5, 6, 7];

/// Difficulties offered in practice mode (expert needs 8x8).
const practiceDifficulties = ['easy', 'medium', 'hard'];

/// Random 31-bit seed for a new practice puzzle.
int newPracticeSeed([Random? random]) =>
    (random ?? Random()).nextInt(0x7FFFFFFF);

/// Generates the practice puzzle for [source] off the UI thread.
@riverpod
Future<Puzzle> practicePuzzle(Ref ref, PracticePuzzleSource source) {
  return Isolate.run(() {
    final generated = generatePuzzle(
      difficulty: Difficulty.parse(source.difficulty),
      seed: source.seed,
      size: source.size,
    );
    return puzzleFromGenerated(
      generated,
      id: 'practice-${source.size}-${source.difficulty}-${source.seed}',
      puzzleDate: 'practice',
    );
  });
}

/// Local-only practice statistics.
class PracticeStats {
  const PracticeStats({
    this.count = 0,
    this.totalTimeSeconds = 0,
    this.bestBySize = const {},
  });

  factory PracticeStats.fromJson(Map<String, dynamic> json) {
    final best = <int, int>{};
    final rawBest = json['best_by_size'];
    if (rawBest is Map<String, dynamic>) {
      for (final entry in rawBest.entries) {
        final size = int.tryParse(entry.key);
        final time = _asInt(entry.value);
        if (size != null && time != null) best[size] = time;
      }
    }
    return PracticeStats(
      count: _asInt(json['count']) ?? 0,
      totalTimeSeconds: _asInt(json['total_time_seconds']) ?? 0,
      bestBySize: best,
    );
  }

  static int? _asInt(Object? value) => value is num ? value.toInt() : null;

  final int count;
  final int totalTimeSeconds;

  /// Best (lowest) solve time per grid size.
  final Map<int, int> bestBySize;

  int get averageTimeSeconds => count == 0 ? 0 : totalTimeSeconds ~/ count;

  Map<String, dynamic> toJson() => {
        'count': count,
        'total_time_seconds': totalTimeSeconds,
        'best_by_size': {
          for (final e in bestBySize.entries) '${e.key}': e.value,
        },
      };

  PracticeStats recordSolve({required int size, required int timeSeconds}) {
    final best = Map<int, int>.from(bestBySize);
    final previous = best[size];
    if (previous == null || timeSeconds < previous) best[size] = timeSeconds;
    return PracticeStats(
      count: count + 1,
      totalTimeSeconds: totalTimeSeconds + timeSeconds,
      bestBySize: best,
    );
  }
}

@Riverpod(keepAlive: true)
class PracticeStatsNotifier extends _$PracticeStatsNotifier {
  @override
  PracticeStats build() => PracticeStats.fromJson(StorageService.practiceStats);

  Future<void> recordSolve({required int size, required int timeSeconds}) async {
    state = state.recordSolve(size: size, timeSeconds: timeSeconds);
    await StorageService.savePracticeStats(state.toJson());
  }
}
