import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:icos/core/backend/auth_client.dart';
import 'package:icos/core/backend/data_api.dart';
import 'package:icos/core/backend/token_store.dart';
import 'package:postgrest/postgrest.dart';

import 'backend_test_helpers.dart';

void main() {
  final now = DateTime.utc(2026, 11, 8, 12);
  late InMemoryTokenStore store;
  late List<http.Request> dataRequests;
  late int tokenCalls;
  late String freshJwt;

  setUp(() {
    store = InMemoryTokenStore();
    dataRequests = [];
    tokenCalls = 0;
    freshJwt = fakeJwt(now.add(const Duration(minutes: 15)));
  });

  /// [data] answers Data API requests; `/auth/token` returns [freshJwt].
  DataApi api(Future<http.Response> Function(http.Request, int n) data) {
    final mock = MockClient((req) async {
      if (req.url.host == 'fn.example.test' && req.url.path == '/auth/token') {
        tokenCalls++;
        return http.Response(jsonEncode({'token': freshJwt}), 200);
      }
      dataRequests.add(req);
      return data(req, dataRequests.length);
    });
    final auth = AuthClient(mock, testConfig, store, clock: () => now);
    return DataApi(testConfig, auth, httpClient: mock);
  }

  http.Response rows() => http.Response(
    jsonEncode([
      {'id': 1},
    ]),
    200,
    headers: {'content-type': 'application/json'},
  );

  test('data_api_always_sends_jwt', () async {
    store
      ..sessionToken = 's'
      ..jwt = 'cached-jwt'
      ..expiry = now.add(const Duration(minutes: 10));
    final db = api((req, _) async => rows());

    final result = await db.from('profiles').select().eq('id', 'u1');
    await db.rpc<dynamic>('get_thing', params: {'p': 1});

    expect(result, [
      {'id': 1},
    ]);
    expect(dataRequests, hasLength(2));
    for (final r in dataRequests) {
      expect(r.headers['Authorization'], 'Bearer cached-jwt');
      expect(r.headers.containsKey('apikey'), isFalse);
    }
    expect(
      dataRequests[0].url.toString(),
      startsWith('https://data.example.test/neondb/rest/v1/profiles?'),
    );
    expect(dataRequests[0].url.queryParameters['id'], 'eq.u1');
    expect(dataRequests[1].method, 'POST');
    expect(dataRequests[1].url.path, '/neondb/rest/v1/rpc/get_thing');
    expect(jsonDecode(dataRequests[1].body), {'p': 1});
    expect(tokenCalls, 0);
  });

  test(
    'a JWT inside the 60 s margin is refreshed before the request',
    () async {
      store
        ..sessionToken = 's'
        ..jwt = 'old'
        ..expiry = now.add(const Duration(seconds: 20));
      final db = api((req, _) async => rows());
      await db.from('puzzles').select();
      expect(tokenCalls, 1);
      expect(dataRequests.single.headers['Authorization'], 'Bearer $freshJwt');
    },
  );

  test('refreshes_expired_jwt_once', () async {
    store
      ..sessionToken = 's'
      ..jwt = 'revoked'
      ..expiry = now.add(const Duration(minutes: 10));
    final db = api(
      (req, n) async => n == 1
          ? http.Response(jsonEncode({'message': 'JWT expired'}), 401)
          : rows(),
    );
    final result = await db.from('profiles').select();
    expect(result, hasLength(1));
    expect(tokenCalls, 1);
    expect(dataRequests, hasLength(2));
    expect(dataRequests[1].headers['Authorization'], 'Bearer $freshJwt');
  });

  test('refreshes_on_400_jwt_message_once', () async {
    store
      ..sessionToken = 's'
      ..jwt = 'stale'
      ..expiry = now.add(const Duration(minutes: 10));
    final db = api(
      (req, _) async => http.Response(
        jsonEncode({'message': 'Invalid token: JWT could not be verified'}),
        400,
      ),
    );
    await expectLater(
      db.rpc<dynamic>('create_group', params: {'p_name': 'x'}),
      throwsA(isA<PostgrestException>()),
    );
    expect(tokenCalls, 1, reason: 'one refresh');
    expect(dataRequests, hasLength(2), reason: 'one retry, no loop');
    expect(jsonDecode(dataRequests[1].body), {'p_name': 'x'});
  });

  test('a 400 unrelated to the JWT is not retried', () async {
    store
      ..sessionToken = 's'
      ..jwt = 'ok'
      ..expiry = now.add(const Duration(minutes: 10));
    final db = api(
      (req, _) async => http.Response(
        jsonEncode({
          'code': '42501',
          'message': 'denied',
          'hint': 'ANONYMOUS_USER',
          'details': null,
        }),
        400,
      ),
    );
    try {
      await db.rpc<dynamic>('create_group');
      fail('expected PostgrestException');
    } on PostgrestException catch (e) {
      expect(e.code, '42501');
      expect(e.hint, 'ANONYMOUS_USER');
    }
    expect(tokenCalls, 0);
    expect(dataRequests, hasLength(1));
  });

  test(
    'PGRST30x code triggers a refresh; a mere "token" word does not',
    () async {
      store
        ..sessionToken = 's'
        ..jwt = 'stale'
        ..expiry = now.add(const Duration(minutes: 10));
      final db = api(
        (req, n) async => n == 1
            ? http.Response(
                jsonEncode({'code': 'PGRST301', 'message': 'expired'}),
                400,
              )
            : rows(),
      );
      await db.from('profiles').select();
      expect(tokenCalls, 1);
      expect(dataRequests, hasLength(2));

      dataRequests.clear();
      tokenCalls = 0;
      final db2 = api(
        (req, _) async => http.Response(
          jsonEncode({
            'code': '22P02',
            'message': 'invalid input syntax near token "x"',
          }),
          400,
        ),
      );
      await expectLater(
        db2.from('profiles').select(),
        throwsA(isA<PostgrestException>()),
      );
      expect(tokenCalls, 0);
      expect(dataRequests, hasLength(1));
    },
  );

  test('no session sends no Authorization header', () async {
    final db = api((req, _) async => rows());
    await db.from('puzzles').select();
    expect(dataRequests.single.headers.containsKey('Authorization'), isFalse);
    expect(tokenCalls, 0);
  });

  group('Prefer header normalisation', () {
    DataApi apiWithJwt() {
      store
        ..sessionToken = 's'
        ..jwt = 'cached-jwt'
        ..expiry = now.add(const Duration(minutes: 10));
      return api((req, _) async => rows());
    }

    Future<void> sendWithPrefer(String? prefer) async {
      final db = apiWithJwt();
      final request = http.Request(
        'GET',
        Uri.parse('${testConfig.dataApiUrl}/profiles'),
      );
      if (prefer != null) request.headers['Prefer'] = prefer;
      await db.client.httpClient!.send(request);
    }

    test('a leading comma is dropped', () async {
      await sendWithPrefer(',return=representation');
      expect(dataRequests.single.headers['Prefer'], 'return=representation');
    });

    test('valid values are kept and trimmed', () async {
      await sendWithPrefer('return=representation, count=exact');
      expect(
        dataRequests.single.headers['Prefer'],
        'return=representation,count=exact',
      );
    });

    test('a lone comma removes the header', () async {
      await sendWithPrefer(',');
      expect(
        dataRequests.single.headers.keys.map((k) => k.toLowerCase()),
        isNot(contains('prefer')),
      );
    });

    test('a request without Prefer is unchanged', () async {
      await sendWithPrefer(null);
      expect(
        dataRequests.single.headers.keys.map((k) => k.toLowerCase()),
        isNot(contains('prefer')),
      );
    });

    test('update().select() reaches the server with a clean Prefer', () async {
      final db = apiWithJwt();
      await db
          .from('profiles')
          .update({'display_name': 'x'})
          .eq('id', 'u1')
          .select();
      final prefer = dataRequests.single.headers['Prefer']!;
      expect(prefer, isNot(startsWith(',')));
      expect(prefer, contains('return=representation'));
    });
  });

  group('no-argument rpc', () {
    test('DataApi.rpc sends {} rather than null', () async {
      store
        ..sessionToken = 's'
        ..jwt = 'cached-jwt'
        ..expiry = now.add(const Duration(minutes: 10));
      final db = api((req, _) async => rows());
      await db.rpc<dynamic>('list_blocked_users');
      expect(dataRequests.single.method, 'POST');
      expect(dataRequests.single.body, '{}');
    });

    test('PostgrestClient.rpc used directly also sends {}', () async {
      store
        ..sessionToken = 's'
        ..jwt = 'cached-jwt'
        ..expiry = now.add(const Duration(minutes: 10));
      final db = api((req, _) async => rows());
      await db.client.rpc<dynamic>('request_account_deletion');
      expect(dataRequests.single.body, '{}');
    });
  });
}
