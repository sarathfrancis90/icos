import 'package:freezed_annotation/freezed_annotation.dart';

part 'streak.freezed.dart';
part 'streak.g.dart';

@freezed
abstract class Streak with _$Streak {
  const factory Streak({
    required String userId,
    required int currentStreak,
    required int longestStreak,
    required int freezeCount,
    String? lastSolveDate,
    String? lastFreezeUsedAt,
  }) = _Streak;

  factory Streak.fromJson(Map<String, dynamic> json) => _$StreakFromJson(json);
}

@freezed
abstract class SolveHistory with _$SolveHistory {
  const factory SolveHistory({
    required String date,
    required int timeSeconds,
    required int hintsUsed,
    required int undosUsed,
    required bool completed,
  }) = _SolveHistory;

  factory SolveHistory.fromJson(Map<String, dynamic> json) =>
      _$SolveHistoryFromJson(json);
}

/// Liveness of a stored streak.
///
/// The server recomputes `streaks.current_streak` only when the player solves
/// or a freeze is applied, so a stored value can outlive a missed day. These
/// helpers give the streak as it stands at [todayUtc].
extension StreakLiveness on Streak {
  /// [currentStreak] if the streak is still alive at [todayUtc], else 0.
  int effectiveCurrentStreak({required DateTime todayUtc}) =>
      effectiveStreakValue(
        currentStreak: currentStreak,
        lastSolveDate: lastSolveDate,
        lastFreezeUsedAt: lastFreezeUsedAt,
        freezeCount: freezeCount,
        todayUtc: todayUtc,
      );
}

/// [currentStreak] when the later of [lastSolveDate] and [lastFreezeUsedAt]
/// (ISO dates; a timestamp is read by its date) is yesterday (UTC) or later,
/// i.e. today's puzzle can still extend it; otherwise 0.
///
/// Also alive when that day is the day before yesterday and a freeze is
/// available ([freezeCount] > 0): the nightly server job (shortly after
/// 00:00 UTC) applies the freeze for yesterday, which the stored row may not
/// reflect yet.
int effectiveStreakValue({
  required int currentStreak,
  required String? lastSolveDate,
  required String? lastFreezeUsedAt,
  required int freezeCount,
  required DateTime todayUtc,
}) {
  if (currentStreak <= 0) return 0;
  final now = todayUtc.toUtc();
  final yesterday = DateTime.utc(now.year, now.month, now.day - 1);
  final days = [
    _utcDay(lastSolveDate),
    _utcDay(lastFreezeUsedAt),
  ].whereType<DateTime>();
  if (days.isEmpty) return 0;
  final latest = days.reduce((a, b) => a.isAfter(b) ? a : b);
  if (!latest.isBefore(yesterday)) return currentStreak;
  final dayBeforeYesterday = DateTime.utc(now.year, now.month, now.day - 2);
  final freezePending = freezeCount > 0 && latest == dayBeforeYesterday;
  return freezePending ? currentStreak : 0;
}

DateTime? _utcDay(String? iso) {
  if (iso == null || iso.length < 10) return null;
  final parsed = DateTime.tryParse(iso.substring(0, 10));
  if (parsed == null) return null;
  return DateTime.utc(parsed.year, parsed.month, parsed.day);
}
