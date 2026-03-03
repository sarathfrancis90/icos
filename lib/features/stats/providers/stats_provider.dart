import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/utils/result.dart';
import '../data/stats_repository.dart';
import '../domain/models/streak.dart';

part 'stats_provider.g.dart';

@riverpod
StatsRepository statsRepository(Ref ref) {
  return StatsRepository();
}

@riverpod
Future<Streak> streak(Ref ref) async {
  final userId = SupabaseService.auth.currentUser?.id;
  if (userId == null) {
    return const Streak(
      userId: '',
      currentStreak: 0,
      longestStreak: 0,
      freezeCount: 0,
    );
  }

  final repo = ref.read(statsRepositoryProvider);
  final result = await repo.getStreak(userId);
  return switch (result) {
    Success(:final data) => data,
    Failure(:final error) => throw error,
  };
}

@riverpod
Future<List<SolveHistory>> solveHistory(Ref ref) async {
  final userId = SupabaseService.auth.currentUser?.id;
  if (userId == null) return [];

  final repo = ref.read(statsRepositoryProvider);
  final result = await repo.getSolveHistory(userId);
  return switch (result) {
    Success(:final data) => data,
    Failure() => [],
  };
}

/// Aggregated stats overview combining streak, total solved, and average time.
@riverpod
Future<StatsOverview> statsOverview(Ref ref) async {
  final userId = SupabaseService.auth.currentUser?.id;
  if (userId == null) {
    return const StatsOverview(
      currentStreak: 0,
      longestStreak: 0,
      totalSolved: 0,
      averageTimeSeconds: 0,
      freezeCount: 0,
      lastFreezeUsedAt: null,
    );
  }

  final repo = ref.read(statsRepositoryProvider);

  // Fetch all stats concurrently.
  final streakFuture = repo.getStreak(userId);
  final totalFuture = repo.getTotalSolved(userId);
  final avgFuture = repo.getAverageTime(userId);

  final streakResult = await streakFuture;
  final totalResult = await totalFuture;
  final avgResult = await avgFuture;

  // Gracefully handle failures for new users with no data
  final streak = switch (streakResult) {
    Success(:final data) => data,
    Failure() => Streak(
        userId: userId,
        currentStreak: 0,
        longestStreak: 0,
        freezeCount: 1,
      ),
  };

  final totalSolved = switch (totalResult) {
    Success(:final data) => data,
    Failure() => 0,
  };

  final avgTime = switch (avgResult) {
    Success(:final data) => data,
    Failure() => 0,
  };

  return StatsOverview(
    currentStreak: streak.currentStreak,
    longestStreak: streak.longestStreak,
    totalSolved: totalSolved,
    averageTimeSeconds: avgTime,
    freezeCount: streak.freezeCount,
    lastFreezeUsedAt: streak.lastFreezeUsedAt,
  );
}

/// Simple data class for aggregated stats.
class StatsOverview {
  const StatsOverview({
    required this.currentStreak,
    required this.longestStreak,
    required this.totalSolved,
    required this.averageTimeSeconds,
    required this.freezeCount,
    required this.lastFreezeUsedAt,
  });

  final int currentStreak;
  final int longestStreak;
  final int totalSolved;
  final int averageTimeSeconds;
  final int freezeCount;
  final String? lastFreezeUsedAt;
}
