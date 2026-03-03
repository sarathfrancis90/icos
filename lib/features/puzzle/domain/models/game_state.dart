import 'package:freezed_annotation/freezed_annotation.dart';
import 'puzzle.dart';

part 'game_state.freezed.dart';

enum CellState { empty, filled, waypoint, wall }

enum GameStatus { notStarted, playing, paused, completed }

@freezed
abstract class GameState with _$GameState {
  const factory GameState({
    required Puzzle puzzle,
    required List<List<CellState>> grid,
    required List<GridPosition> path,
    required int currentWaypointIndex,
    required int elapsedSeconds,
    required int hintsUsed,
    required int undosUsed,
    required GameStatus status,
    @Default(false) bool isSubmitting,
    GridPosition? hintCell,
  }) = _GameState;
}

@freezed
abstract class GridPosition with _$GridPosition {
  const factory GridPosition({
    required int row,
    required int col,
  }) = _GridPosition;
}
