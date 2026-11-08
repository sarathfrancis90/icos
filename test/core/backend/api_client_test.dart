import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:icos/core/backend/api_client.dart';
import 'package:icos/core/backend/token_store.dart';

import 'backend_test_helpers.dart';

void main() {
  late List<http.Request> requests;
  late InMemoryTokenStore store;

  setUp(() {
    requests = [];
    store = InMemoryTokenStore(sessionToken: 'session-1');
  });

  ApiClient api(http.Response Function(http.Request) handler) => ApiClient(
    MockClient((req) async {
      requests.add(req);
      return handler(req);
    }),
    testConfig,
    store,
  );

  test('invoke POSTs /api/<name> with the session bearer', () async {
    final client = api(
      (_) => http.Response(jsonEncode({'nonce': 'n', 'code': null}), 200),
    );
    final res = await client.invoke('start-puzzle', {'date': '2026-11-08'});
    final req = requests.single;
    expect(req.method, 'POST');
    expect(req.url.toString(), 'https://fn.example.test/api/start-puzzle');
    expect(req.headers['authorization'], 'Bearer session-1');
    expect(jsonDecode(req.body), {'date': '2026-11-08'});
    expect(res.status, 200);
    expect(res.json, {'nonce': 'n', 'code': null});
  });

  test('error status and code are returned, not thrown', () async {
    final client = api(
      (_) => http.Response(
        jsonEncode({'error': 'Already solved', 'code': 'ALREADY_COMPLETED'}),
        409,
      ),
    );
    final res = await client.invoker('submit-score', {});
    expect(res.status, 409);
    expect(res.code, 'ALREADY_COMPLETED');
  });

  test('non-JSON and empty bodies', () async {
    var body = '<html>Bad gateway</html>';
    final client = api((_) => http.Response(body, 502));
    final html = await client.invoke('join-group', {});
    expect(html.status, 502);
    expect(html.body, '<html>Bad gateway</html>');
    expect(html.json, isNull);
    expect(html.code, isNull);

    body = '';
    final empty = await client.invoke('join-group', {});
    expect(empty.status, 502);
    expect(empty.body, isNull);
  });

  test('transport failures throw', () async {
    final client = ApiClient(
      MockClient((_) async => throw http.ClientException('offline')),
      testConfig,
      store,
    );
    expect(client.invoke('report', {}), throwsA(isA<http.ClientException>()));
  });

  test('no session sends no bearer', () async {
    store.sessionToken = null;
    final client = api((_) => http.Response('{}', 401));
    await client.invoke('block', {});
    expect(requests.single.headers.containsKey('authorization'), isFalse);
  });

  test('unauthenticated_config_uses_public_route', () async {
    final client = api(
      (_) => http.Response(
        jsonEncode({
          'config': {'maintenance_mode': false},
        }),
        200,
      ),
    );
    final res = await client.get('config', public: true);
    final req = requests.single;
    expect(req.method, 'GET');
    expect(req.url.toString(), 'https://fn.example.test/api/config');
    expect(req.headers.containsKey('authorization'), isFalse);
    expect(res.json?['config'], {'maintenance_mode': false});
  });

  test('authenticated GET carries the bearer', () async {
    final client = api((_) => http.Response('{}', 200));
    await client.get('export-data');
    expect(requests.single.headers['authorization'], 'Bearer session-1');
  });
}
