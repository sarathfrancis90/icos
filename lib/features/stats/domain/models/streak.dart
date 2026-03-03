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
