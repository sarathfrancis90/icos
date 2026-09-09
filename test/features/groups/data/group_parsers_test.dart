import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:icos/core/utils/app_error.dart';
import 'package:icos/features/groups/data/group_parsers.dart';
import 'package:icos/features/groups/domain/models/group.dart';

const _groupJson = {
  'id': 'g-1',
  'name': 'Sunday Solvers',
  'description': 'Family group',
  'invite_code': 'ABC123',
  'admin_id': 'u-admin',
  'member_count': 3,
  'max_members': 50,
  'is_active': true,
  'created_at': '2026-09-01T10:00:00Z',
};

void main() {
  group('Group.fromJson', () {
    test('parses a full row', () {
      final group = Group.fromJson(_groupJson);
      expect(group.id, 'g-1');
      expect(group.inviteCode, 'ABC123');
      expect(group.adminId, 'u-admin');
      expect(group.memberCount, 3);
      expect(group.maxMembers, 50);
      expect(group.isActive, isTrue);
      expect(group.createdAt.isUtc, isTrue);
    });

    test('tolerates numeric strings and null description', () {
      final group = Group.fromJson({
        ..._groupJson,
        'description': null,
        'member_count': '7',
        'max_members': 50.0,
        'is_active': 't',
      });
      expect(group.description, '');
      expect(group.memberCount, 7);
      expect(group.maxMembers, 50);
      expect(group.isActive, isTrue);
    });
  });

  group('GroupParsers.parseGroupRow (create_group RPC)', () {
    test('accepts a single object', () {
      expect(GroupParsers.parseGroupRow(_groupJson).id, 'g-1');
    });

    test('accepts a one-element list', () {
      expect(GroupParsers.parseGroupRow([_groupJson]).id, 'g-1');
    });

    test('accepts a JSON string', () {
      expect(GroupParsers.parseGroupRow(jsonEncode(_groupJson)).id, 'g-1');
    });

    test('throws FormatException on empty payload', () {
      expect(() => GroupParsers.parseGroupRow(null), throwsFormatException);
      expect(() => GroupParsers.parseGroupRow(<Object>[]), throwsFormatException);
    });
  });

  group('GroupParsers.parseJoinGroupResponse', () {
    test('parses {group: {...}} as a Map', () {
      final group = GroupParsers.parseJoinGroupResponse({'group': _groupJson});
      expect(group.name, 'Sunday Solvers');
    });

    test('parses {group: {...}} as a JSON string', () {
      final group = GroupParsers.parseJoinGroupResponse(
        jsonEncode({'group': _groupJson}),
      );
      expect(group.inviteCode, 'ABC123');
    });

    test('tolerates a bare group row', () {
      expect(GroupParsers.parseJoinGroupResponse(_groupJson).id, 'g-1');
    });

    test('throws when group is missing', () {
      expect(
        () => GroupParsers.parseJoinGroupResponse({'ok': true}),
        throwsFormatException,
      );
    });
  });

  group('GroupParsers.parseJoinGroupError', () {
    test('ALREADY_MEMBER carries group_id', () {
      final failure = GroupParsers.parseJoinGroupError(409, {
        'error': 'Already a member',
        'code': 'ALREADY_MEMBER',
        'group_id': 'g-9',
      });
      expect(failure.code, JoinGroupErrorCode.alreadyMember);
      expect(failure.groupId, 'g-9');
    });

    test('GROUP_FULL maps to validation error with server message', () {
      final failure = GroupParsers.parseJoinGroupError(
        409,
        jsonEncode({'error': 'Group is full', 'code': 'GROUP_FULL'}),
      );
      expect(failure.code, JoinGroupErrorCode.groupFull);
      expect(failure.error, isA<ValidationError>());
      expect(failure.error.userMessage, 'Group is full');
    });

    test('ANONYMOUS_USER maps to auth error', () {
      final failure = GroupParsers.parseJoinGroupError(403, {
        'error': 'Anonymous users cannot join groups',
        'code': 'ANONYMOUS_USER',
      });
      expect(failure.code, JoinGroupErrorCode.anonymousUser);
      expect(failure.error, isA<AuthError>());
    });

    test('404 without code maps to invalid code / notFound', () {
      final failure =
          GroupParsers.parseJoinGroupError(404, {'error': 'Invalid invite code'});
      expect(failure.code, JoinGroupErrorCode.invalidCode);
      expect(failure.error, isA<NotFoundError>());
    });

    test('unparseable body falls back to unknown', () {
      final failure = GroupParsers.parseJoinGroupError(500, 'boom');
      expect(failure.code, JoinGroupErrorCode.other);
      expect(failure.error, isA<UnknownError>());
    });
  });

  group('GroupLeaderboardEntry.fromJson (daily)', () {
    test('parses a full row including rank, undos and verified', () {
      final entry = GroupLeaderboardEntry.fromJson({
        'rank': 1,
        'user_id': 'u-1',
        'display_name': 'Alice',
        'avatar_url': null,
        'time_seconds': 83,
        'hints_used': 1,
        'undos_used': 2,
        'completed': true,
        'verified': false,
      });
      expect(entry.rank, 1);
      expect(entry.displayName, 'Alice');
      expect(entry.timeSeconds, 83);
      expect(entry.hintsUsed, 1);
      expect(entry.undosUsed, 2);
      expect(entry.completed, isTrue);
      expect(entry.verified, isFalse);
    });

    test('defaults missing fields and coerces strings/bigints', () {
      final entry = GroupLeaderboardEntry.fromJson({
        'rank': '3',
        'user_id': 'u-2',
        'display_name': 'Bob',
        'time_seconds': '120',
        'hints_used': 0.0,
        'completed': 'true',
      });
      expect(entry.rank, 3);
      expect(entry.timeSeconds, 120);
      expect(entry.hintsUsed, 0);
      expect(entry.undosUsed, 0);
      expect(entry.completed, isTrue);
      expect(entry.verified, isTrue, reason: 'verified defaults to true');
    });

    test('parseDailyLeaderboard handles list payloads', () {
      final entries = GroupParsers.parseDailyLeaderboard([
        {'rank': 1, 'user_id': 'a', 'display_name': 'A', 'completed': true},
        {'rank': 2, 'user_id': 'b', 'display_name': 'B', 'completed': false},
      ]);
      expect(entries.map((e) => e.rank), [1, 2]);
    });
  });

  group('WeeklyLeaderboardEntry.fromJson', () {
    test('parses avg_time_seconds as num', () {
      final entry = WeeklyLeaderboardEntry.fromJson({
        'rank': 1,
        'user_id': 'u-1',
        'display_name': 'Alice',
        'completed_count': 5,
        'avg_time_seconds': 93.4,
        'total_hints': 2,
      });
      expect(entry.completedCount, 5);
      expect(entry.avgTimeSeconds, closeTo(93.4, 0.001));
      expect(entry.avgTimeSecondsRounded, 93);
      expect(entry.totalHints, 2);
    });

    test('parses avg_time_seconds as a numeric string (PostgREST numeric)', () {
      final entry = WeeklyLeaderboardEntry.fromJson({
        'rank': '2',
        'user_id': 'u-2',
        'display_name': 'Bob',
        'completed_count': '3',
        'avg_time_seconds': '101.6666666667',
        'total_hints': '0',
      });
      expect(entry.rank, 2);
      expect(entry.completedCount, 3);
      expect(entry.avgTimeSecondsRounded, 102);
      expect(entry.totalHints, 0);
    });

    test('null avg_time_seconds stays null', () {
      final entry = WeeklyLeaderboardEntry.fromJson({
        'rank': 4,
        'user_id': 'u-4',
        'display_name': 'Dee',
        'completed_count': 0,
        'avg_time_seconds': null,
        'total_hints': 0,
      });
      expect(entry.avgTimeSeconds, isNull);
      expect(entry.avgTimeSecondsRounded, isNull);
    });
  });

  group('GroupMember.fromJson', () {
    test('lifts display_name/avatar_url from embedded profiles object', () {
      final member = GroupMember.fromJson({
        'id': 'm-1',
        'group_id': 'g-1',
        'user_id': 'u-1',
        'role': 'admin',
        'joined_at': '2026-09-01T10:00:00Z',
        'profiles': {'display_name': 'Alice', 'avatar_url': 'https://x/a.png'},
      });
      expect(member.displayName, 'Alice');
      expect(member.avatarUrl, 'https://x/a.png');
      expect(member.isAdmin, isTrue);
    });

    test('handles profiles returned as a list and missing profile', () {
      final fromList = GroupMember.fromJson({
        'id': 'm-2',
        'group_id': 'g-1',
        'user_id': 'u-2',
        'role': 'member',
        'joined_at': '2026-09-01T10:00:00Z',
        'profiles': [
          {'display_name': 'Bob', 'avatar_url': null},
        ],
      });
      expect(fromList.displayName, 'Bob');
      expect(fromList.isAdmin, isFalse);

      final noProfile = GroupMember.fromJson({
        'id': 'm-3',
        'group_id': 'g-1',
        'user_id': 'u-3',
        'role': 'member',
        'joined_at': '2026-09-01T10:00:00Z',
        'profiles': null,
      });
      expect(noProfile.displayName, isNull);
    });
  });

  group('GroupFeedEvent.fromJson', () {
    test('parses a realtime payload without the profile join', () {
      final event = GroupFeedEvent.fromJson({
        'id': 'f-1',
        'group_id': 'g-1',
        'user_id': 'u-1',
        'puzzle_date': '2026-09-09',
        'event': 'solved',
        'created_at': '2026-09-09T08:00:00Z',
      });
      expect(event.event, 'solved');
      expect(event.puzzleDate, '2026-09-09');
      expect(event.displayName, isNull);
    });

    test('parses a joined row with profiles', () {
      final events = GroupParsers.parseFeed([
        {
          'id': 'f-2',
          'group_id': 'g-1',
          'user_id': 'u-2',
          'puzzle_date': null,
          'event': 'joined',
          'created_at': '2026-09-09T08:00:00Z',
          'profiles': {'display_name': 'Bob', 'avatar_url': null},
        },
      ]);
      expect(events.single.displayName, 'Bob');
      expect(events.single.puzzleDate, isNull);
    });
  });
}
