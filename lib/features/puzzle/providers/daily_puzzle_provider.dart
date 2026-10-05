import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/services/connectivity_service.dart';
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
  var servedBundled = false;

  // The offline fallback is only a stand-in: ask the server again as soon as
  // the network is back so the real puzzle replaces it.
  ref.listen(connectivityNotifierProvider, (prev, next) {
    if (next && prev == false && servedBundled) ref.invalidateSelf();
  });

  final result = await repo.getPuzzle(date);
  return switch (result) {
    Success(data: final puzzle) => () {
      servedBundled = puzzle.origin == PuzzleOrigin.bundled;
      return puzzle;
    }(),
    Failure(error: final error) => throw error,
  };
}

/// Today's (UTC) puzzle.
@riverpod
Future<Puzzle> dailyPuzzle(Ref ref) =>
    ref.watch(puzzleForDateProvider(AppDateUtils.todayUtc()).future);
