import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:icos/core/services/edge_function_client.dart';
import 'package:icos/core/utils/app_error.dart';
import 'package:icos/core/utils/result.dart';
import 'package:icos/features/groups/data/group_repository.dart';

import '../../../helpers/data_api_test_helpers.dart';

/// Tables and RPCs go through a real PostgREST client over [handler]; the
/// `/api/*` routes through [routes].
GroupRepository _repo({
  Future<http.Response> Function(http.Request request)? handler,
  FakeRoutes? routes,
  String? userId = 'u-1',
}) => GroupRepository(
  client: () => testDataApi(
    handler ?? (_) async => fail('unexpected Data API request'),
  ),
  invoker: (routes ?? FakeRoutes()).invoke,
  userId: () => userId,
);

void main() {
  group('blockUser', () {
    test('posts {user_id} to /api/block', () async {
      final routes = FakeRoutes((_, _) => const EdgeResponse(200, {'blocked': true}));
      final repo = _repo(routes: routes);

      final result = await repo.blockUser('u-2');

      expect(result, isA<Success<void, AppError>>());
      expect(routes.calls.single.name, 'block');
      expect(routes.calls.single.body, {'user_id': 'u-2'});
    });

    test('maps a 404 to AppError.notFound', () async {
      final repo = _repo(
        routes: FakeRoutes(
          (_, _) => const EdgeResponse(404, {
            'error': 'User not found',
            'code': 'PROFILE_NOT_FOUND',
          }),
        ),
      );

      final result = await repo.blockUser('u-2');

      final error = (result as Failure<void, AppError>).error;
      expect(error, isA<NotFoundError>());
      expect(error.userMessage, 'User not found');
    });

    test('maps a 5xx to AppError.network', () async {
      final repo = _repo(
        routes: FakeRoutes((_, _) => const EdgeResponse(503, null)),
      );

      final result = await repo.blockUser('u-2');

      expect((result as Failure<void, AppError>).error, isA<NetworkError>());
    });

    test('maps a SocketException to AppError.network', () async {
      final repo = GroupRepository(
        client: () => testDataApi((_) async => fail('no Data API call')),
        invoker: (_, _) async => throw const SocketException('offline'),
        userId: () => 'u-1',
      );

      final result = await repo.blockUser('u-2');

      expect(result, isA<Failure<void, AppError>>());
      expect((result as Failure<void, AppError>).error, isA<NetworkError>());
    });

    test('requires a signed-in user', () async {
      final routes = FakeRoutes();
      final repo = _repo(routes: routes, userId: null);

      final result = await repo.blockUser('u-2');

      expect((result as Failure<void, AppError>).error, isA<AuthError>());
      expect(routes.calls, isEmpty);
    });
  });

  group('unblockUser', () {
    test('posts {user_id} to /api/unblock', () async {
      final routes = FakeRoutes(
        (_, _) => const EdgeResponse(200, {'blocked': false}),
      );
      final repo = _repo(routes: routes);

      final result = await repo.unblockUser('u-2');

      expect(result, isA<Success<void, AppError>>());
      expect(routes.calls.single.name, 'unblock');
      expect(routes.calls.single.body, {'user_id': 'u-2'});
    });

    test('maps failures', () async {
      final repo = GroupRepository(
        client: () => testDataApi((_) async => fail('no Data API call')),
        invoker: (_, _) async => throw const SocketException('offline'),
        userId: () => 'u-1',
      );
      final result = await repo.unblockUser('u-2');
      expect((result as Failure<void, AppError>).error, isA<NetworkError>());
    });
  });

  group('reports', () {
    test('reportUser posts the target, reason and trimmed details', () async {
      final routes = FakeRoutes((_, _) => const EdgeResponse(201, {'id': 'r-1'}));
      final repo = _repo(routes: routes);

      final result = await repo.reportUser(
        userId: 'u-2',
        reason: 'harassment',
        details: '  rude  ',
      );

      expect(result, isA<Success<void, AppError>>());
      expect(routes.calls.single.name, 'report');
      expect(routes.calls.single.body, {
        'reported_user_id': 'u-2',
        'reason': 'harassment',
        'details': 'rude',
      });
    });

    test('reportGroup posts reported_group_id', () async {
      final routes = FakeRoutes((_, _) => const EdgeResponse(201, {'id': 'r-2'}));
      final repo = _repo(routes: routes);

      final result = await repo.reportGroup(groupId: 'g-1', reason: 'spam');

      expect(result, isA<Success<void, AppError>>());
      expect(routes.calls.single.body, {
        'reported_group_id': 'g-1',
        'reason': 'spam',
        'details': '',
      });
    });

    test('maps a 400 to a validation error and a 429 to rate limit', () async {
      final invalid = _repo(
        routes: FakeRoutes(
          (_, _) => const EdgeResponse(400, {
            'error': 'Invalid reason',
            'code': 'INVALID_FIELD',
          }),
        ),
      );
      final limited = _repo(
        routes: FakeRoutes(
          (_, _) => const EdgeResponse(429, {'code': 'RATE_LIMITED'}),
        ),
      );

      final a = await invalid.reportUser(userId: 'u-2', reason: 'x');
      final b = await limited.reportUser(userId: 'u-2', reason: 'spam');

      expect((a as Failure<void, AppError>).error, isA<ValidationError>());
      expect((b as Failure<void, AppError>).error, isA<RateLimitError>());
    });

    test('requires a signed-in user', () async {
      final routes = FakeRoutes();
      final repo = _repo(routes: routes, userId: null);

      final result = await repo.reportUser(userId: 'u-2', reason: 'spam');

      expect((result as Failure<void, AppError>).error, isA<AuthError>());
      expect(routes.calls, isEmpty);
    });
  });

  group('listBlockedUsers', () {
    test('parses rows from the list_blocked_users RPC', () async {
      late http.Request seen;
      final repo = _repo(
        handler: (request) async {
          seen = request;
          return jsonResponse([
            {
              'user_id': 'u-2',
              'display_name': 'Bob',
              'blocked_at': '2026-10-05T10:00:00Z',
            },
            {
              'user_id': 'u-3',
              'display_name': 'Deleted User',
              'blocked_at': '2026-10-04T10:00:00Z',
            },
          ]);
        },
      );

      final result = await repo.listBlockedUsers();

      expect(seen.method, 'POST');
      expect(seen.url.toString(), '$testDataApiUrl/rpc/list_blocked_users');
      final users = (result as Success<List<dynamic>, AppError>).data;
      expect(users.map((u) => u.userId), ['u-2', 'u-3']);
      expect(users.first.displayName, 'Bob');
    });

    test('returns an empty list when nothing is blocked', () async {
      final repo = _repo(handler: (_) async => jsonResponse(<Object>[]));
      final result = await repo.listBlockedUsers();
      expect((result as Success<List<dynamic>, AppError>).data, isEmpty);
    });

    test('maps a PostgrestException to AppError.database', () async {
      final repo = _repo(
        handler: (_) async => jsonResponse({
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
      final repo = _repo(
        handler: (_) async => throw const SocketException('offline'),
      );
      final result = await repo.listBlockedUsers();
      expect(
        (result as Failure<List<dynamic>, AppError>).error,
        isA<NetworkError>(),
      );
    });

    test('a signed-out caller gets an empty list without a request', () async {
      final repo = _repo(userId: null);
      final result = await repo.listBlockedUsers();
      expect((result as Success<List<dynamic>, AppError>).data, isEmpty);
    });
  });

  test('request bodies are JSON', () async {
    // Guard against the RPC helper sending form bodies.
    late http.Request seen;
    final repo = _repo(
      handler: (request) async {
        seen = request;
        return http.Response('', 204);
      },
    );
    await repo.leaveGroup('g-1');
    expect(seen.url.toString(), '$testDataApiUrl/rpc/leave_group');
    expect(jsonDecode(seen.body), {'p_group_id': 'g-1'});
  });
}
