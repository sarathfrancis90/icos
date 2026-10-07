import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/services/storage_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/utils/app_error.dart';
import '../../../core/utils/date_utils.dart';
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
  return loadSolveHistory(ref.read(statsRepositoryProvider), userId);
}

/// Aggregated stats overview combining streak, total solved, and average time.
///
/// A backend failure never becomes zeros: it falls back to the last good copy
/// (flagged [StatsOverview.fromCache]) or, with no copy, throws so the screen
/// shows its error + retry state.
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
  return loadStatsOverview(ref.read(statsRepositoryProvider), userId);
}

/// Streak from the last saved stats overview of [userId] as it stands today
/// (0 once it has lapsed), or `null` when there is no usable copy (or storage
/// is unavailable). Used when the server cannot be reached, e.g. to decide on
/// the streak reminder.
int? cachedCurrentStreak(String? userId) {
  if (userId == null) return null;
  try {
    final cached = StorageService.getStatsCache('overview', userId: userId);
    return cached == null
        ? null
        : StatsOverview.tryFromJson(cached)?.withLiveStreak().currentStreak;
  } catch (_) {
    return null;
  }
}

/// Fetches the overview; caches it on success, serves the cache on failure.
Future<StatsOverview> loadStatsOverview(
  StatsRepository repo,
  String userId,
) async {
  final results = await Future.wait<Object>([
    repo.getStreak(userId),
    repo.getTotalSolved(userId),
    repo.getAverageTime(userId),
  ]);
  final streakResult = results[0] as Result<Streak, AppError>;
  final totalResult = results[1] as Result<int, AppError>;
  final avgResult = results[2] as Result<int, AppError>;

  if (streakResult case Success(data: final streak)) {
    if (totalResult case Success(data: final total)) {
      if (avgResult case Success(data: final avg)) {
        final fresh = StatsOverview(
          currentStreak: streak.effectiveCurrentStreak(
            todayUtc: AppDateUtils.nowUtc(),
          ),
          longestStreak: streak.longestStreak,
          totalSolved: total,
          averageTimeSeconds: avg,
          freezeCount: streak.freezeCount,
          lastFreezeUsedAt: streak.lastFreezeUsedAt,
          lastSolveDate: streak.lastSolveDate,
        );
        await StorageService.saveStatsCache(
          'overview',
          fresh.toJson(),
          userId: userId,
        );
        return fresh;
      }
    }
  }

  final cached = StorageService.getStatsCache('overview', userId: userId);
  if (cached != null) {
    final overview = StatsOverview.tryFromJson(cached);
    if (overview != null) return overview.withLiveStreak().copyAsCached();
  }
  final error = switch ((streakResult, totalResult, avgResult)) {
    (Failure(:final error), _, _) => error,
    (_, Failure(:final error), _) => error,
    (_, _, Failure(:final error)) => error,
    _ => const AppError.unknown('Stats unavailable'),
  };
  throw error;
}

/// Fetches recent solves; caches on success, serves the cache on failure and
/// throws when there is no cached copy.
Future<List<SolveHistory>> loadSolveHistory(
  StatsRepository repo,
  String userId,
) async {
  final result = await repo.getSolveHistory(userId);
  switch (result) {
    case Success(:final data):
      await StorageService.saveStatsCache('history', {
        'items': data.map((h) => h.toJson()).toList(),
      }, userId: userId);
      return data;
    case Failure(:final error):
      final cached = StorageService.getStatsCache('history', userId: userId);
      final items = cached?['items'];
      if (items is List) {
        try {
          return [
            for (final row in items)
              SolveHistory.fromJson(Map<String, dynamic>.from(row as Map)),
          ];
        } catch (_) {
          // Corrupt cache: treat as missing.
        }
      }
      throw error;
  }
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
    this.lastSolveDate,
    this.fromCache = false,
  });

  /// True when the backend was unreachable and this is the last saved copy.
  final bool fromCache;

  StatsOverview copyAsCached() => _copy(fromCache: true);

  /// This overview with [currentStreak] as it stands at the current UTC day:
  /// 0 once neither a solve nor a freeze covers yesterday.
  StatsOverview withLiveStreak() => _copy(
    currentStreak: effectiveStreakValue(
      currentStreak: currentStreak,
      lastSolveDate: lastSolveDate,
      lastFreezeUsedAt: lastFreezeUsedAt,
      freezeCount: freezeCount,
      todayUtc: AppDateUtils.nowUtc(),
    ),
  );

  StatsOverview _copy({int? currentStreak, bool? fromCache}) => StatsOverview(
    currentStreak: currentStreak ?? this.currentStreak,
    longestStreak: longestStreak,
    totalSolved: totalSolved,
    averageTimeSeconds: averageTimeSeconds,
    freezeCount: freezeCount,
    lastFreezeUsedAt: lastFreezeUsedAt,
    lastSolveDate: lastSolveDate,
    fromCache: fromCache ?? this.fromCache,
  );

  Map<String, dynamic> toJson() => {
    'currentStreak': currentStreak,
    'longestStreak': longestStreak,
    'totalSolved': totalSolved,
    'averageTimeSeconds': averageTimeSeconds,
    'freezeCount': freezeCount,
    'lastFreezeUsedAt': lastFreezeUsedAt,
    'lastSolveDate': lastSolveDate,
  };

  /// The saved overview, or `null` when it is unreadable. A copy saved
  /// before `lastSolveDate` was stored cannot be checked for a lapsed streak
  /// and counts as unreadable.
  static StatsOverview? tryFromJson(Map<String, dynamic> json) {
    if (!json.containsKey('lastSolveDate')) return null;
    try {
      return StatsOverview(
        currentStreak: json['currentStreak'] as int,
        longestStreak: json['longestStreak'] as int,
        totalSolved: json['totalSolved'] as int,
        averageTimeSeconds: json['averageTimeSeconds'] as int,
        freezeCount: json['freezeCount'] as int,
        lastFreezeUsedAt: json['lastFreezeUsedAt'] as String?,
        lastSolveDate: json['lastSolveDate'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  final int currentStreak;
  final int longestStreak;
  final int totalSolved;
  final int averageTimeSeconds;
  final int freezeCount;
  final String? lastFreezeUsedAt;

  /// Last solved puzzle date (ISO, UTC), used to tell a lapsed streak.
  final String? lastSolveDate;
}
