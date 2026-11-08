import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:icos/core/services/edge_function_client.dart';
import 'package:icos/core/utils/app_error.dart';
import 'package:icos/core/utils/result.dart';
import 'package:icos/features/groups/data/group_repository.dart';

import '../../../helpers/data_api_test_helpers.dart';

GroupRepository _repo(
  Future<http.Response> Function(http.Request request) handler, {
  String? userId = 'u-1',
  FakeRoutes? routes,
}) => GroupRepository(
  client: () => testDataApi(handler),
  invoker: (routes ?? FakeRoutes()).invoke,
  userId: () => userId,
);

http.Response _json(Object body, [int status = 200]) =>
    jsonResponse(body, status);

const _groupRow = {
  'id': 'g-1',
  'name': 'Sunday Solvers',
  'description': '',
  'invite_code': 'ABC123',
  'admin_id': 'u-1',
  'member_count': 2,
  'max_members': 50,
  'is_active': true,
  'created_at': '2026-09-01T00:00:00Z',
};

void main() {
  group('regenerateInviteCode', () {
    test('calls the RPC and parses the returned group row', () async {
      late http.Request seen;
      final repo = _repo((request) async {
        seen = request;
        return _json({
          'id': 'g-1',
          'name': 'Sunday Solvers',
          'description': '',
          'invite_code': 'NEW456',
          'admin_id': 'u-1',
          'member_count': 2,
          'max_members': 50,
          'is_active': true,
          'created_at': '2026-09-01T00:00:00Z',
        });
      });

      final result = await repo.regenerateInviteCode('g-1');

      expect(seen.url.toString(), '$testDataApiUrl/rpc/regenerate_invite_code');
      expect(jsonDecode(seen.body), {'p_group_id': 'g-1'});
      expect((result as Success).data.inviteCode, 'NEW456');
    });

    test('maps a server exception to a validation error', () async {
      final repo = _repo(
        (_) async => _json({
          'code': 'P0001',
          'message': 'Only the group admin can do that',
          'details': null,
          'hint': null,
        }, 400),
      );

      final result = await repo.regenerateInviteCode('g-1');

      expect((result as Failure).error, isA<ValidationError>());
    });

    test('maps a permission error (42501) to an auth error', () async {
      final repo = _repo(
        (_) async => _json({
          'code': '42501',
          'message': 'permission denied',
          'details': null,
          'hint': null,
        }, 403),
      );

      final result = await repo.regenerateInviteCode('g-1');

      final error = (result as Failure).error as AppError;
      expect(error, isA<AuthError>());
      expect(error.userMessage, 'You do not have permission to do that');
    });

    test('requires a signed-in user', () async {
      final repo = _repo((_) async => _json({}), userId: null);

      final result = await repo.regenerateInviteCode('g-1');

      expect((result as Failure).error, isA<AuthError>());
    });
  });

  group('joinGroup', () {
    test('posts the normalised code to /api/join-group', () async {
      final routes = FakeRoutes(
        (_, _) => const EdgeResponse(200, {
          'group': _groupRow,
          'already_member': false,
        }),
      );
      final repo = _repo((_) async => fail('no Data API call'), routes: routes);

      final result = await repo.joinGroup('abc123');

      expect(routes.calls.single.name, 'join-group');
      expect(routes.calls.single.body, {'invite_code': 'ABC123'});
      expect((result as Success).data.id, 'g-1');
    });

    test('ALREADY_MEMBER fetches the existing group from the Data API', () async {
      late http.Request seen;
      final repo = _repo(
        (request) async {
          seen = request;
          return _json(_groupRow);
        },
        routes: FakeRoutes(
          (_, _) => const EdgeResponse(409, {
            'error': 'Already a member',
            'code': 'ALREADY_MEMBER',
            'group_id': 'g-1',
          }),
        ),
      );

      final result = await repo.joinGroup('ABC123');

      expect(seen.url.path, endsWith('/groups'));
      expect(seen.url.queryParameters['id'], 'eq.g-1');
      expect((result as Success).data.id, 'g-1');
    });

    test('GROUP_FULL is a validation error', () async {
      final repo = _repo(
        (_) async => fail('no Data API call'),
        routes: FakeRoutes(
          (_, _) => const EdgeResponse(409, {
            'error': 'This group is full',
            'code': 'GROUP_FULL',
          }),
        ),
      );

      final result = await repo.joinGroup('ABC123');

      expect((result as Failure).error, isA<ValidationError>());
    });
  });

  group('getGroupFeed', () {
    test('selects the embed, newest id first, limited to 50', () async {
      late http.Request seen;
      final repo = _repo((request) async {
        seen = request;
        return _json(<Object>[]);
      });

      await repo.getGroupFeed('g-1');

      expect(seen.url.toString(), startsWith('$testDataApiUrl/group_feed?'));
      final q = seen.url.queryParameters;
      expect(q['select'], '*,profiles(display_name,avatar_url)');
      expect(q['group_id'], 'eq.g-1');
      expect(q['order'], startsWith('id.desc'));
      expect(q['limit'], '50');
      expect(q.containsKey('id'), isFalse);
    });

    test('afterId adds id=gt.<lastId>', () async {
      late http.Request seen;
      final repo = _repo((request) async {
        seen = request;
        return _json([
          {
            'id': 43,
            'group_id': 'g-1',
            'user_id': 'u-2',
            'puzzle_date': '2026-11-08',
            'event': 'solved',
            'created_at': '2026-11-08T10:00:00Z',
            'profiles': {'display_name': 'Bob', 'avatar_url': null},
          },
        ]);
      });

      final result = await repo.getGroupFeed('g-1', afterId: '42');

      expect(seen.url.queryParameters['id'], 'gt.42');
      final events = (result as Success).data as List;
      expect(events.single.id, '43');
      expect(events.single.displayName, 'Bob');
    });
  });

  group('reads', () {
    test('getMyGroups treats 42501 as no groups', () async {
      final repo = _repo(
        (_) async => _json({
          'code': '42501',
          'message': 'permission denied',
          'details': null,
          'hint': null,
        }, 403),
      );

      final result = await repo.getMyGroups();

      expect((result as Success).data, isEmpty);
    });

    test('a P0001 HINT error keeps the server wording', () async {
      final repo = _repo(
        (_) async => _json({
          'code': 'P0001',
          'message': 'Only the group admin can do that',
          'details': null,
          'hint': 'NOT_ADMIN',
        }, 400),
      );

      final result = await repo.deleteGroup('g-1');

      final error = (result as Failure).error as AppError;
      expect(error, isA<ValidationError>());
      expect(error.userMessage, 'Only the group admin can do that');
    });
  });
}
