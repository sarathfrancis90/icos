import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:icos/core/utils/app_error.dart';
import 'package:icos/core/utils/result.dart';
import 'package:icos/features/groups/data/group_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Drives the real [SupabaseClient] against an in-memory HTTP handler, so the
/// repository is exercised through PostgREST's actual request/response and
/// error handling.
GroupRepository _repo(
  Future<http.Response> Function(http.Request request) handler, {
  String? userId = 'u-1',
}) {
  final client = SupabaseClient(
    'http://localhost:54321',
    'anon-key',
    // PostgREST reads `response.request`, which MockClient leaves unset.
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
  group('blockUser', () {
    test('calls the block_user RPC with the target id', () async {
      late http.Request seen;
      final repo = _repo((request) async {
        seen = request;
        return http.Response('', 204);
      });

      final result = await repo.blockUser('u-2');

      expect(result, isA<Success<void, AppError>>());
      expect(seen.url.path, endsWith('/rpc/block_user'));
      expect(jsonDecode(seen.body), {'p_user_id': 'u-2'});
    });

    test('maps a PostgrestException to AppError.database', () async {
      final repo = _repo(
        (_) async => _json({
          'code': 'XX000',
          'message': 'boom',
          'details': null,
          'hint': null,
        }, 400),
      );

      final result = await repo.blockUser('u-2');

      expect(result, isA<Failure<void, AppError>>());
      expect((result as Failure<void, AppError>).error, isA<DatabaseError>());
    });

    test('maps a SocketException to AppError.network', () async {
      final repo = _repo((_) async => throw const SocketException('offline'));

      final result = await repo.blockUser('u-2');

      expect(result, isA<Failure<void, AppError>>());
      expect((result as Failure<void, AppError>).error, isA<NetworkError>());
    });

    test('requires a signed-in user', () async {
      var called = false;
      final repo = _repo((_) async {
        called = true;
        return http.Response('', 204);
      }, userId: null);

      final result = await repo.blockUser('u-2');

      expect((result as Failure<void, AppError>).error, isA<AuthError>());
      expect(called, isFalse);
    });
  });

  group('unblockUser', () {
    test('calls the unblock_user RPC', () async {
      late http.Request seen;
      final repo = _repo((request) async {
        seen = request;
        return http.Response('', 204);
      });

      final result = await repo.unblockUser('u-2');

      expect(result, isA<Success<void, AppError>>());
      expect(seen.url.path, endsWith('/rpc/unblock_user'));
      expect(jsonDecode(seen.body), {'p_user_id': 'u-2'});
    });

    test('maps failures', () async {
      final repo = _repo((_) async => throw const SocketException('offline'));
      final result = await repo.unblockUser('u-2');
      expect((result as Failure<void, AppError>).error, isA<NetworkError>());
    });
  });

  group('listBlockedUsers', () {
    test('parses rows from list_blocked_users', () async {
      final repo = _repo((request) async {
        expect(request.url.path, endsWith('/rpc/list_blocked_users'));
        return _json([
          {
            'user_id': 'u-2',
            'display_name': 'Bob',
            'blocked_at': '2026-10-05T10:00:00+00:00',
          },
          {
            'user_id': 'u-3',
            'display_name': 'Deleted User',
            'blocked_at': '2026-10-04T10:00:00+00:00',
          },
        ]);
      });

      final result = await repo.listBlockedUsers();

      final users = (result as Success<List<dynamic>, AppError>).data;
      expect(users.map((u) => u.userId), ['u-2', 'u-3']);
      expect(users.first.displayName, 'Bob');
    });

    test('returns an empty list when nothing is blocked', () async {
      final repo = _repo((_) async => _json(<Object>[]));
      final result = await repo.listBlockedUsers();
      expect((result as Success<List<dynamic>, AppError>).data, isEmpty);
    });

    test('maps a PostgrestException to AppError.database', () async {
      final repo = _repo(
        (_) async => _json({
          'code': 'XX000',
          'message': 'boom',
          'details': null,
          'hint': null,
        }, 400),
      );
      final result = await repo.listBlockedUsers();
      expect(
        (result as Failure<List<dynamic>, AppError>).error,
        isA<DatabaseError>(),
      );
    });

    test('maps a SocketException to AppError.network', () async {
      final repo = _repo((_) async => throw const SocketException('offline'));
      final result = await repo.listBlockedUsers();
      expect(
        (result as Failure<List<dynamic>, AppError>).error,
        isA<NetworkError>(),
      );
    });
  });
}
