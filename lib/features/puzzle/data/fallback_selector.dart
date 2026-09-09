import '../domain/solver/puzzle_core.dart';

// Uses the solver core's `fnv1a32` (stable across platforms and Dart
// versions, unlike `String.hashCode`) so every device picks the same
// fallback for a date.

/// Picks the bundled fallback puzzle for [date].
///
/// Candidates whose `difficulty` matches the weekday difficulty of [date]
/// are preferred so the fallback feels like the real schedule (Mon/Tue easy …
/// Sun expert); ties are broken with [fnv1a32]. Falls back to hashing over
/// the whole list when nothing matches. Returns -1 for an empty list.
int selectFallbackIndex(String date, List<Map<String, dynamic>> puzzles) {
  if (puzzles.isEmpty) return -1;
  final wanted = weekdayDifficulty(date).name;
  final candidates = <int>[
    for (var i = 0; i < puzzles.length; i++)
      if (puzzles[i]['difficulty'] == wanted) i,
  ];
  final hash = fnv1a32(date);
  if (candidates.isEmpty) return hash % puzzles.length;
  return candidates[hash % candidates.length];
}
