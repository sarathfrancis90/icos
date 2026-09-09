import 'dart:convert';

import '../../../core/utils/app_error.dart';
import '../domain/models/group.dart';

/// Pure, network-free parsing helpers for the groups backend contract.
///
/// Kept separate from [GroupRepository] so they can be unit-tested with
/// fake JSON without initialising Supabase.
abstract final class GroupParsers {
  /// Decodes a raw function/RPC payload that may arrive as a JSON string,
  /// a `Map`, or a `List`.
  static Object? decode(Object? data) {
    if (data is String) {
      if (data.trim().isEmpty) return null;
      try {
        return jsonDecode(data);
      } on FormatException {
        return data;
      }
    }
    return data;
  }

  static Map<String, dynamic>? asMap(Object? data) {
    final decoded = decode(data);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return null;
  }

  static List<Map<String, dynamic>> asRows(Object? data) {
    final decoded = decode(data);
    if (decoded is List) {
      return decoded
          .whereType<Map<dynamic, dynamic>>()
          .map(Map<String, dynamic>.from)
          .toList();
    }
    final single = asMap(decoded);
    return single == null ? const [] : [single];
  }

  /// A `returns groups` RPC yields a single object, but some PostgREST
  /// versions wrap set-returning results in a one-element list.
  static Group parseGroupRow(Object? data) {
    final rows = asRows(data);
    if (rows.isEmpty) {
      throw const FormatException('Empty group payload');
    }
    return Group.fromJson(rows.first);
  }

  /// Parses the 200 body of the `join-group` edge function:
  /// `{group: {...}}` (also tolerates a bare group row).
  static Group parseJoinGroupResponse(Object? data) {
    final map = asMap(data);
    if (map == null) {
      throw const FormatException('Unexpected join-group response');
    }
    final groupJson = map['group'];
    if (groupJson is Map) {
      return Group.fromJson(Map<String, dynamic>.from(groupJson));
    }
    if (map.containsKey('invite_code')) {
      return Group.fromJson(map);
    }
    throw const FormatException('join-group response is missing "group"');
  }

  /// Interprets a non-2xx `join-group` body.
  static JoinGroupFailure parseJoinGroupError(int status, Object? details) {
    final body = asMap(details);
    final code = body?['code']?.toString();
    final message = body?['error']?.toString();

    switch (code) {
      case 'ALREADY_MEMBER':
        return JoinGroupFailure(
          code: JoinGroupErrorCode.alreadyMember,
          groupId: body?['group_id']?.toString(),
          error: AppError.validation(message ?? 'You are already a member'),
        );
      case 'GROUP_FULL':
        return JoinGroupFailure(
          code: JoinGroupErrorCode.groupFull,
          error: AppError.validation(message ?? 'This group is full'),
        );
      case 'ANONYMOUS_USER':
        return JoinGroupFailure(
          code: JoinGroupErrorCode.anonymousUser,
          error: AppError.auth(
            message ?? 'Create an account to join groups',
          ),
        );
    }

    return switch (status) {
      404 => JoinGroupFailure(
          code: JoinGroupErrorCode.invalidCode,
          error: AppError.notFound(message ?? 'Invalid invite code'),
        ),
      401 || 403 => JoinGroupFailure(
          code: JoinGroupErrorCode.anonymousUser,
          error: AppError.auth(message ?? 'Sign in to join groups'),
        ),
      409 => JoinGroupFailure(
          code: JoinGroupErrorCode.groupFull,
          error: AppError.validation(message ?? 'Unable to join this group'),
        ),
      429 => JoinGroupFailure(
          code: JoinGroupErrorCode.other,
          error: AppError.rateLimit(message ?? 'Too many requests'),
        ),
      _ => JoinGroupFailure(
          code: JoinGroupErrorCode.other,
          error: AppError.unknown(message ?? 'Failed to join group'),
        ),
    };
  }

  static List<GroupLeaderboardEntry> parseDailyLeaderboard(Object? data) {
    return asRows(data).map(GroupLeaderboardEntry.fromJson).toList();
  }

  static List<WeeklyLeaderboardEntry> parseWeeklyLeaderboard(Object? data) {
    return asRows(data).map(WeeklyLeaderboardEntry.fromJson).toList();
  }

  static List<GroupMember> parseMembers(Object? data) {
    return asRows(data).map(GroupMember.fromJson).toList();
  }

  static List<GroupFeedEvent> parseFeed(Object? data) {
    return asRows(data).map(GroupFeedEvent.fromJson).toList();
  }
}

enum JoinGroupErrorCode { alreadyMember, groupFull, anonymousUser, invalidCode, other }

class JoinGroupFailure {
  const JoinGroupFailure({
    required this.code,
    required this.error,
    this.groupId,
  });

  final JoinGroupErrorCode code;
  final AppError error;

  /// Populated for [JoinGroupErrorCode.alreadyMember].
  final String? groupId;
}
