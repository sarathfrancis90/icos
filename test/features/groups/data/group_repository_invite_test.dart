import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:icos/core/utils/app_error.dart';
import 'package:icos/core/utils/result.dart';
import 'package:icos/features/groups/data/group_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

GroupRepository _repo(
  Future<http.Response> Function(http.Request request) handler, {
  String? userId = 'u-1',
}) {
  final client = SupabaseClient(
    'http://localhost:54321',
    'anon-key',
    httpClient: MockClient((request) async {
      final r = await handler(request);
      return http.Response(
        r.body,
        r.statusCode,
        headers: r.headers,
        request: request,
      );
    }),
  );
  return GroupRepository(client: client, userIdOverride: () => userId);
}

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

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

      expect(seen.url.path, endsWith('/rpc/regenerate_invite_code'));
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

    test('requires a signed-in user', () async {
      final repo = _repo((_) async => _json({}), userId: null);

      final result = await repo.regenerateInviteCode('g-1');

      expect((result as Failure).error, isA<AuthError>());
    });
  });
}
