import 'package:freezed_annotation/freezed_annotation.dart';

part 'group.freezed.dart';
part 'group.g.dart';

@freezed
sealed class Group with _$Group {
  const factory Group({
    required String id,
    required String name,
    required String description,
    required String inviteCode,
    required String adminId,
    required int memberCount,
    required int maxMembers,
    required bool isActive,
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
    required String role,
    required DateTime joinedAt,
    String? displayName,
    String? avatarUrl,
  }) = _GroupMember;

  factory GroupMember.fromJson(Map<String, dynamic> json) =>
      _$GroupMemberFromJson(json);
}

@freezed
sealed class GroupLeaderboardEntry with _$GroupLeaderboardEntry {
  const factory GroupLeaderboardEntry({
    required String userId,
    required String displayName,
    String? avatarUrl,
    required int timeSeconds,
    required int hintsUsed,
    required int rank,
    required bool completed,
  }) = _GroupLeaderboardEntry;

  factory GroupLeaderboardEntry.fromJson(Map<String, dynamic> json) =>
      _$GroupLeaderboardEntryFromJson(json);
}
