// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';

part 'puzzle.freezed.dart';
part 'puzzle.g.dart';

/// Where a [Puzzle] came from.
///
/// A [bundled] puzzle is one of the offline fallbacks shipped in the app. It
/// is shown under today's date when the real puzzle cannot be loaded, but it
/// is not the real puzzle: solving it must never be submitted, queued or
/// stored as the result for that date.
enum PuzzleOrigin { server, bundled }

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
    int? difficultyScore,

    /// Set by the repository, never serialised: anything parsed from JSON is
    /// a server puzzle.
    @JsonKey(includeFromJson: false, includeToJson: false)
    @Default(PuzzleOrigin.server)
    PuzzleOrigin origin,
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
