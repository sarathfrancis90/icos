import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/storage_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/utils/app_error.dart';
import '../../../core/utils/result.dart';
import '../domain/models/puzzle.dart';

class PuzzleRepository {
  /// Fetch today's puzzle, with cache-first strategy.
  Future<Result<Puzzle, AppError>> getDailyPuzzle(String date) async {
    // 1. Check local cache
    final cached = StorageService.getCachedPuzzle(date);
    if (cached != null) {
      return Result.success(Puzzle.fromJson(cached));
    }

    // 2. Fetch from Supabase
    try {
      final response = await SupabaseService.client
          .from('puzzles')
          .select()
          .eq('puzzle_date', date)
          .maybeSingle();

      if (response != null) {
        final puzzle = Puzzle.fromJson(response);
        await StorageService.cachePuzzle(date, response);
        return Result.success(puzzle);
      }
    } on PostgrestException catch (e) {
      // Fall through to fallback
      return Result.failure(AppError.database(e.message));
    } catch (_) {
      // Network error — fall through to fallback
    }

    // 3. Load fallback puzzle
    return _loadFallbackPuzzle(date);
  }

  /// Submit a puzzle attempt to the server.
  Future<Result<void, AppError>> submitAttempt(
    PuzzleAttempt attempt,
  ) async {
    try {
      await SupabaseService.client
          .from('puzzle_attempts')
          .insert(attempt.toJson());
      return const Result.success(null);
    } on PostgrestException catch (e) {
      return Result.failure(AppError.database(e.message));
    } catch (e) {
      return Result.failure(AppError.network(e.toString()));
    }
  }

  /// Check if user has already completed today's puzzle.
  Future<bool> hasCompletedPuzzle(String userId, String date) async {
    try {
      final response = await SupabaseService.client
          .from('puzzle_attempts')
          .select('id')
          .eq('user_id', userId)
          .eq('puzzle_date', date)
          .eq('completed', true)
          .maybeSingle();
      return response != null;
    } catch (_) {
      return false;
    }
  }

  Future<Result<Puzzle, AppError>> _loadFallbackPuzzle(String date) async {
    try {
      final jsonString =
          await rootBundle.loadString('assets/puzzles/fallback_puzzles.json');
      final List<dynamic> puzzles = jsonDecode(jsonString) as List<dynamic>;

      // Pick a fallback based on the date hash
      final dateHash = date.hashCode.abs();
      final index = dateHash % puzzles.length;
      final puzzleJson = puzzles[index] as Map<String, dynamic>;

      // Override the date to match
      puzzleJson['puzzle_date'] = date;

      final puzzle = Puzzle.fromJson(puzzleJson);
      return Result.success(puzzle);
    } catch (e) {
      return const Result.failure(AppError.unknown('Failed to load fallback puzzle'));
    }
  }

  /// Pre-cache tomorrow's puzzle.
  Future<void> preCacheTomorrowPuzzle(String tomorrowDate) async {
    final cached = StorageService.getCachedPuzzle(tomorrowDate);
    if (cached != null) return;

    try {
      final response = await SupabaseService.client
          .from('puzzles')
          .select()
          .eq('puzzle_date', tomorrowDate)
          .maybeSingle();

      if (response != null) {
        await StorageService.cachePuzzle(tomorrowDate, response);
      }
    } catch (_) {
      // Silent failure for pre-cache
    }
  }
}
