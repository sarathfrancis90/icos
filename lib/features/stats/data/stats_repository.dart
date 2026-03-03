import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/utils/app_error.dart';
import '../../../core/utils/result.dart';
import '../domain/models/streak.dart';

class StatsRepository {
  /// Fetch the user's streak record from the streaks table.
  Future<Result<Streak, AppError>> getStreak(String userId) async {
    try {
      final response = await SupabaseService.client
          .from('streaks')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      if (response == null) {
        return Result.success(
          Streak(
            userId: userId,
            currentStreak: 0,
            longestStreak: 0,
            freezeCount: 1,
          ),
        );
      }

      final streak = Streak(
        userId: response['user_id'] as String,
        currentStreak: response['current_streak'] as int,
        longestStreak: response['longest_streak'] as int,
        freezeCount: response['freeze_count'] as int,
        lastSolveDate: response['last_solve_date'] as String?,
        lastFreezeUsedAt: response['last_freeze_used_at'] as String?,
      );

      return Result.success(streak);
    } on PostgrestException catch (e) {
      return Result.failure(AppError.database(e.message));
    } catch (e) {
      return Result.failure(AppError.network(e.toString()));
    }
  }

  /// Fetch recent solve history from the puzzle_attempts table.
  Future<Result<List<SolveHistory>, AppError>> getSolveHistory(
    String userId, {
    int limit = 30,
  }) async {
    try {
      final response = await SupabaseService.client
          .from('puzzle_attempts')
          .select('puzzle_date, time_seconds, hints_used, undos_used, completed')
          .eq('user_id', userId)
          .order('puzzle_date', ascending: false)
          .limit(limit);

      final history = (response as List<dynamic>).map((row) {
        final map = row as Map<String, dynamic>;
        return SolveHistory(
          date: map['puzzle_date'] as String,
          timeSeconds: map['time_seconds'] as int,
          hintsUsed: map['hints_used'] as int,
          undosUsed: map['undos_used'] as int,
          completed: map['completed'] as bool,
        );
      }).toList();

      return Result.success(history);
    } on PostgrestException catch (e) {
      return Result.failure(AppError.database(e.message));
    } catch (e) {
      return Result.failure(AppError.network(e.toString()));
    }
  }

  /// Count of completed puzzle attempts for the user.
  Future<Result<int, AppError>> getTotalSolved(String userId) async {
    try {
      final response = await SupabaseService.client
          .from('puzzle_attempts')
          .select('id')
          .eq('user_id', userId)
          .eq('completed', true);

      return Result.success((response as List).length);
    } on PostgrestException catch (e) {
      return Result.failure(AppError.database(e.message));
    } catch (e) {
      return Result.failure(AppError.network(e.toString()));
    }
  }

  /// Average solve time in seconds for completed puzzles.
  Future<Result<int, AppError>> getAverageTime(String userId) async {
    try {
      final response = await SupabaseService.client
          .from('puzzle_attempts')
          .select('time_seconds')
          .eq('user_id', userId)
          .eq('completed', true);

      final rows = response as List<dynamic>;
      if (rows.isEmpty) {
        return const Result.success(0);
      }

      final totalSeconds = rows.fold<int>(
        0,
        (sum, row) => sum + ((row as Map<String, dynamic>)['time_seconds'] as int),
      );

      return Result.success(totalSeconds ~/ rows.length);
    } on PostgrestException catch (e) {
      return Result.failure(AppError.database(e.message));
    } catch (e) {
      return Result.failure(AppError.network(e.toString()));
    }
  }
}
