import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/utils/date_utils.dart';
import '../../../core/utils/result.dart';
import '../data/puzzle_repository.dart';
import '../domain/models/puzzle.dart';

part 'daily_puzzle_provider.g.dart';

@riverpod
PuzzleRepository puzzleRepository(Ref ref) {
  return PuzzleRepository();
}

@riverpod
Future<Puzzle> dailyPuzzle(Ref ref) async {
  final repo = ref.read(puzzleRepositoryProvider);
  final today = AppDateUtils.todayUtc();
  final result = await repo.getDailyPuzzle(today);
  return switch (result) {
    Success(data: final puzzle) => puzzle,
    Failure(error: final error) => throw error,
  };
}
