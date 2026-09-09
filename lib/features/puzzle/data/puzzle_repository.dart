import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/app_logger.dart';
import '../../../core/services/edge_function_client.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/utils/app_error.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/result.dart';
import '../domain/models/puzzle.dart';
import 'fallback_selector.dart';
import 'submission_result.dart';

/// Public columns of the `puzzles` table (the solution is never selected).
const puzzlePublicColumns =
    'id, puzzle_date, grid_size, waypoints, walls, difficulty, '
    'par_time_seconds, difficulty_score';

const _attemptColumns =
    'puzzle_date, time_seconds, hints_used, undos_used, completed, verified, '
    'is_archive, path, completed_at';

class PuzzleRepository {
  PuzzleRepository({EdgeInvoker? invoker})
    : _invoke = invoker ?? supabaseEdgeInvoke;

  final EdgeInvoker _invoke;

  /// Puzzle for [date]: cache → `puzzles` table → (today/tomorrow only)
  /// `daily-puzzle` edge function → bundled fallback.
  Future<Result<Puzzle, AppError>> getPuzzle(String date) async {
    final cached = StorageService.getCachedPuzzle(date);
    if (cached != null) {
      try {
        return Result.success(Puzzle.fromJson(cached));
      } catch (e) {
        AppLogger.warn('Corrupt cached puzzle; refetching', error: e);
      }
    }

    final fromTable = await _fetchFromTable(date);
    if (fromTable != null) return Result.success(fromTable);

    if (AppDateUtils.isTodayOrTomorrowUtc(date)) {
      final generated = await _requestGeneration(date);
      if (generated != null) return Result.success(generated);
    }

    return _loadFallbackPuzzle(date);
  }

  /// Backwards-compatible alias.
  Future<Result<Puzzle, AppError>> getDailyPuzzle(String date) =>
      getPuzzle(date);

  Future<Puzzle?> _fetchFromTable(String date) async {
    try {
      final response = await SupabaseService.client
          .from('puzzles')
          .select(puzzlePublicColumns)
          .eq('puzzle_date', date)
          .maybeSingle()
          .timeout(const Duration(seconds: 10));
      if (response == null) return null;
      await StorageService.cachePuzzle(date, response);
      return Puzzle.fromJson(response);
    } on PostgrestException catch (e) {
      AppLogger.warn('puzzles select failed', error: e, data: {'date': date});
      return null;
    } catch (e) {
      AppLogger.debug('puzzles select unreachable', error: e);
      return null;
    }
  }

  Future<Puzzle?> _requestGeneration(String date) async {
    try {
      final response = await _invoke('daily-puzzle', {'date': date});
      if (response.status != 200 && response.status != 201) {
        AppLogger.warn(
          'daily-puzzle failed',
          data: {
            'date': date,
            'status': response.status,
            'code': response.code,
          },
        );
        return null;
      }
      final puzzleJson = response.json?['puzzle'];
      if (puzzleJson is! Map<String, dynamic>) return null;
      final public = <String, dynamic>{
        'id': puzzleJson['id'],
        'puzzle_date': puzzleJson['puzzle_date'],
        'grid_size': puzzleJson['grid_size'],
        'waypoints': puzzleJson['waypoints'],
        'walls': puzzleJson['walls'],
        'difficulty': puzzleJson['difficulty'],
        'par_time_seconds': puzzleJson['par_time_seconds'],
        'difficulty_score': puzzleJson['difficulty_score'],
      };
      final puzzle = Puzzle.fromJson(public);
      await StorageService.cachePuzzle(date, public);
      return puzzle;
    } catch (e) {
      AppLogger.debug('daily-puzzle unreachable', error: e);
      return null;
    }
  }

  Future<Result<Puzzle, AppError>> _loadFallbackPuzzle(String date) async {
    try {
      final jsonString = await rootBundle.loadString(
        'assets/puzzles/fallback_puzzles.json',
      );
      final puzzles = (jsonDecode(jsonString) as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final index = selectFallbackIndex(date, puzzles);
      if (index < 0) {
        return const Result.failure(AppError.notFound('No fallback puzzles'));
      }
      final puzzleJson = Map<String, dynamic>.from(puzzles[index])
        ..['puzzle_date'] = date;
      return Result.success(Puzzle.fromJson(puzzleJson));
    } catch (e, st) {
      AppLogger.error('Fallback puzzle load failed', error: e, st: st);
      return const Result.failure(
        AppError.unknown('Failed to load fallback puzzle'),
      );
    }
  }

  /// Pre-cache tomorrow's puzzle (table only; generation is the cron's job).
  Future<void> preCacheTomorrowPuzzle([String? tomorrowDate]) async {
    final date = tomorrowDate ?? AppDateUtils.tomorrowUtc();
    if (StorageService.getCachedPuzzle(date) != null) return;
    await _fetchFromTable(date);
  }

  /// The signed-in user's completed attempt for [date], or `null`.
  Future<SubmissionResult?> getOwnAttempt(String userId, String date) async {
    try {
      final row = await SupabaseService.client
          .from('puzzle_attempts')
          .select(_attemptColumns)
          .eq('user_id', userId)
          .eq('puzzle_date', date)
          .eq('completed', true)
          .maybeSingle()
          .timeout(const Duration(seconds: 10));
      if (row == null) return null;
      return attemptRowToResult(row);
    } catch (e) {
      AppLogger.debug('own attempt lookup failed', error: e);
      return null;
    }
  }

  /// Completed attempts for dates in `[from, to]` (inclusive, ISO strings).
  /// Dates in [from, to] (inclusive, YYYY-MM-DD) that have a puzzle row on the
  /// server. Used by the archive so we never list days that cannot be played.
  Future<Result<List<String>, AppError>> getAvailableDates({
    required String from,
    required String to,
  }) async {
    try {
      final rows = await SupabaseService.client
          .from('puzzles')
          .select('puzzle_date')
          .gte('puzzle_date', from)
          .lte('puzzle_date', to)
          .order('puzzle_date', ascending: false);
      return Result.success([for (final r in rows) r['puzzle_date'] as String]);
    } on PostgrestException catch (e) {
      return Result.failure(AppError.database(e.message));
    } catch (e) {
      return Result.failure(AppError.network(e.toString()));
    }
  }

  Future<Result<List<SubmissionResult>, AppError>> getOwnAttempts(
    String userId, {
    required String from,
    required String to,
  }) async {
    try {
      final rows = await SupabaseService.client
          .from('puzzle_attempts')
          .select(_attemptColumns)
          .eq('user_id', userId)
          .eq('completed', true)
          .gte('puzzle_date', from)
          .lte('puzzle_date', to)
          .order('puzzle_date', ascending: false)
          .timeout(const Duration(seconds: 10));
      return Result.success([for (final row in rows) attemptRowToResult(row)]);
    } on PostgrestException catch (e) {
      return Result.failure(AppError.database(e.message));
    } catch (e) {
      return Result.failure(AppError.network(e.toString()));
    }
  }

  /// Maps a `puzzle_attempts` row to a [SubmissionResult].
  static SubmissionResult attemptRowToResult(Map<String, dynamic> row) {
    final rawPath = (row['path'] as List<dynamic>?) ?? const [];
    return SubmissionResult(
      date: row['puzzle_date'] as String,
      status: (row['verified'] as bool? ?? false)
          ? SubmissionStatus.verified
          : SubmissionStatus.unverified,
      timeSeconds: (row['time_seconds'] as num?)?.toInt() ?? 0,
      hintsUsed: (row['hints_used'] as num?)?.toInt() ?? 0,
      undosUsed: (row['undos_used'] as num?)?.toInt() ?? 0,
      path: [
        for (final cell in rawPath)
          if (cell is List && cell.length >= 2)
            [(cell[0] as num).toInt(), (cell[1] as num).toInt()],
      ],
      completedAt:
          DateTime.tryParse(row['completed_at'] as String? ?? '')?.toUtc() ??
          DateTime.now().toUtc(),
      isArchive: row['is_archive'] as bool? ?? false,
    );
  }
}
