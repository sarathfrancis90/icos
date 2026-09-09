import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/services/edge_function_client.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/result.dart';
import '../data/puzzle_repository.dart';
import '../domain/models/puzzle.dart';

part 'daily_puzzle_provider.g.dart';

@Riverpod(keepAlive: true)
PuzzleRepository puzzleRepository(Ref ref) {
  return PuzzleRepository(invoker: ref.watch(edgeInvokerProvider));
}

/// Puzzle for an ISO [date] (cache → table → daily-puzzle → bundled).
@riverpod
Future<Puzzle> puzzleForDate(Ref ref, String date) async {
  final repo = ref.read(puzzleRepositoryProvider);
  final result = await repo.getPuzzle(date);
  return switch (result) {
    Success(data: final puzzle) => puzzle,
    Failure(error: final error) => throw error,
  };
}

/// Today's (UTC) puzzle.
@riverpod
Future<Puzzle> dailyPuzzle(Ref ref) =>
    ref.watch(puzzleForDateProvider(AppDateUtils.todayUtc()).future);
