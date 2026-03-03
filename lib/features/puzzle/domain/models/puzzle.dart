import 'package:freezed_annotation/freezed_annotation.dart';

part 'puzzle.freezed.dart';
part 'puzzle.g.dart';

@freezed
abstract class Puzzle with _$Puzzle {
  const factory Puzzle({
    required String id,
    required String puzzleDate,
    required int gridSize,
    required List<Waypoint> waypoints,
    required List<Wall> walls,
    required String difficulty,
    required int parTimeSeconds,
    String? solutionHash,
  }) = _Puzzle;

  factory Puzzle.fromJson(Map<String, dynamic> json) => _$PuzzleFromJson(json);
}

@freezed
abstract class Waypoint with _$Waypoint {
  const factory Waypoint({
    required int order,
    required int row,
    required int col,
  }) = _Waypoint;

  factory Waypoint.fromJson(Map<String, dynamic> json) =>
      _$WaypointFromJson(json);
}

@freezed
abstract class Wall with _$Wall {
  const factory Wall({
    required int row,
    required int col,
  }) = _Wall;

  factory Wall.fromJson(Map<String, dynamic> json) => _$WallFromJson(json);
}

@freezed
abstract class PuzzleAttempt with _$PuzzleAttempt {
  const factory PuzzleAttempt({
    String? id,
    required String puzzleId,
    required String userId,
    required String puzzleDate,
    required int timeSeconds,
    required int hintsUsed,
    required int undosUsed,
    required bool completed,
    required List<List<int>> path,
    DateTime? completedAt,
  }) = _PuzzleAttempt;

  factory PuzzleAttempt.fromJson(Map<String, dynamic> json) =>
      _$PuzzleAttemptFromJson(json);
}
