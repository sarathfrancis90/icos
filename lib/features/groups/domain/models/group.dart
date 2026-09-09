// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';

part 'group.freezed.dart';
part 'group.g.dart';

// ─── Defensive JSON helpers ────────────────────────────────────────────
// PostgREST returns `numeric` columns as strings and RPC row shapes may
// vary slightly between deployments, so every numeric/boolean field on the
// leaderboard/feed models goes through these lenient converters.

int _asInt(Object? value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) {
    return int.tryParse(value) ?? double.tryParse(value)?.round() ?? 0;
  }
  return 0;
}

int? _asIntOrNull(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) {
    return int.tryParse(value) ?? double.tryParse(value)?.round();
  }
  return null;
}

double? _asDoubleOrNull(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

bool _asBool(Object? value) => _asBoolWithFallback(value, fallback: false);

bool _asBoolWithFallback(Object? value, {required bool fallback}) {
  if (value == null) return fallback;
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final lower = value.toLowerCase();
    if (lower == 'true' || lower == 't' || lower == '1') return true;
    if (lower == 'false' || lower == 'f' || lower == '0') return false;
  }
  return fallback;
}

bool _asBoolDefaultTrue(Object? value) =>
    _asBoolWithFallback(value, fallback: true);

String _asString(Object? value) => value?.toString() ?? '';

String? _asStringOrNull(Object? value) {
  if (value == null) return null;
  final s = value.toString();
  return s.isEmpty ? null : s;
}

/// Extracts `display_name`/`avatar_url` from an embedded `profiles` object
/// (PostgREST returns an object for many-to-one joins, but a list when the
/// relationship is ambiguous) and lifts them to top-level keys.
Map<String, dynamic> flattenProfileJoin(Map<String, dynamic> row) {
  final raw = row['profiles'];
  Map<String, dynamic>? profile;
  if (raw is Map<String, dynamic>) {
    profile = raw;
  } else if (raw is List && raw.isNotEmpty && raw.first is Map) {
    profile = Map<String, dynamic>.from(raw.first as Map);
  }
  if (profile == null) return row;
  return {
    ...row,
    'display_name': row['display_name'] ?? profile['display_name'],
    'avatar_url': row['avatar_url'] ?? profile['avatar_url'],
  };
}

@freezed
sealed class Group with _$Group {
  const factory Group({
    required String id,
    required String name,
    @JsonKey(fromJson: _asString) @Default('') String description,
    required String inviteCode,
    required String adminId,
    @JsonKey(fromJson: _asInt) @Default(1) int memberCount,
    @JsonKey(fromJson: _asInt) @Default(50) int maxMembers,
    @JsonKey(fromJson: _asBoolDefaultTrue) @Default(true) bool isActive,
    required DateTime createdAt,
  }) = _Group;

  factory Group.fromJson(Map<String, dynamic> json) => _$GroupFromJson(json);
}

@freezed
sealed class GroupMember with _$GroupMember {
  const factory GroupMember({
    required String id,
    required String groupId,
    required String userId,
    @JsonKey(fromJson: _asString) @Default('member') String role,
    required DateTime joinedAt,
    @JsonKey(fromJson: _asStringOrNull) String? displayName,
    @JsonKey(fromJson: _asStringOrNull) String? avatarUrl,
  }) = _GroupMember;

  const GroupMember._();

  factory GroupMember.fromJson(Map<String, dynamic> json) =>
      _$GroupMemberFromJson(flattenProfileJoin(json));

  bool get isAdmin => role == 'admin';
}

/// Row returned by `get_group_daily_leaderboard(p_group_id, p_puzzle_date)`.
@freezed
sealed class GroupLeaderboardEntry with _$GroupLeaderboardEntry {
  const factory GroupLeaderboardEntry({
    @JsonKey(fromJson: _asInt) @Default(0) int rank,
    required String userId,
    @JsonKey(fromJson: _asString) @Default('') String displayName,
    @JsonKey(fromJson: _asStringOrNull) String? avatarUrl,
    @JsonKey(fromJson: _asInt) @Default(0) int timeSeconds,
    @JsonKey(fromJson: _asInt) @Default(0) int hintsUsed,
    @JsonKey(fromJson: _asInt) @Default(0) int undosUsed,
    @JsonKey(fromJson: _asBool) @Default(false) bool completed,
    @JsonKey(fromJson: _asBoolDefaultTrue) @Default(true) bool verified,
  }) = _GroupLeaderboardEntry;

  factory GroupLeaderboardEntry.fromJson(Map<String, dynamic> json) =>
      _$GroupLeaderboardEntryFromJson(json);
}

/// Row returned by `get_group_weekly_leaderboard(p_group_id, p_week_start)`.
///
/// `avg_time_seconds` is a Postgres `numeric`, which PostgREST serialises as
/// a JSON string; it is parsed leniently into a nullable double.
@freezed
sealed class WeeklyLeaderboardEntry with _$WeeklyLeaderboardEntry {
  const factory WeeklyLeaderboardEntry({
    @JsonKey(fromJson: _asInt) @Default(0) int rank,
    required String userId,
    @JsonKey(fromJson: _asString) @Default('') String displayName,
    @JsonKey(fromJson: _asStringOrNull) String? avatarUrl,
    @JsonKey(fromJson: _asInt) @Default(0) int completedCount,
    @JsonKey(fromJson: _asDoubleOrNull) double? avgTimeSeconds,
    @JsonKey(fromJson: _asInt) @Default(0) int totalHints,
  }) = _WeeklyLeaderboardEntry;

  const WeeklyLeaderboardEntry._();

  factory WeeklyLeaderboardEntry.fromJson(Map<String, dynamic> json) =>
      _$WeeklyLeaderboardEntryFromJson(json);

  /// Rounded average time, or `null` when the member has no solves.
  int? get avgTimeSecondsRounded => avgTimeSeconds?.round();
}

/// Row of the realtime-enabled `group_feed` table, optionally enriched with
/// the actor's profile via `select('*, profiles(display_name, avatar_url)')`.
@freezed
sealed class GroupFeedEvent with _$GroupFeedEvent {
  const factory GroupFeedEvent({
    @JsonKey(fromJson: _asString) required String id,
    required String groupId,
    required String userId,
    @JsonKey(fromJson: _asStringOrNull) String? puzzleDate,
    @JsonKey(fromJson: _asString) @Default('') String event,
    required DateTime createdAt,
    @JsonKey(fromJson: _asStringOrNull) String? displayName,
    @JsonKey(fromJson: _asStringOrNull) String? avatarUrl,
    @JsonKey(fromJson: _asIntOrNull) int? timeSeconds,
  }) = _GroupFeedEvent;

  const GroupFeedEvent._();

  factory GroupFeedEvent.fromJson(Map<String, dynamic> json) =>
      _$GroupFeedEventFromJson(flattenProfileJoin(json));
}
