import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:icos/core/backend/backend_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _env = {
  'API_BASE_URL': 'https://env-api.example.test/',
  'DATA_API_URL': 'https://env-data.example.test/neondb/rest/v1',
  'GOOGLE_WEB_CLIENT_ID': 'web-id',
};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('dotenv defaults are normalised', () {
    final c = BackendConfig.fromEnv(_env);
    expect(c.apiBaseUrl, 'https://env-api.example.test');
    expect(
      c.authUri('sign-in/anonymous').toString(),
      'https://env-api.example.test/auth/sign-in/anonymous',
    );
    expect(
      c.apiUri('config').toString(),
      'https://env-api.example.test/api/config',
    );
    expect(c.googleWebClientId, 'web-id');
  });

  test('remote JSON overrides dotenv and is cached', () async {
    final prefs = await SharedPreferences.getInstance();
    Uri? requested;
    final client = MockClient((req) async {
      requested = req.url;
      return http.Response(
        jsonEncode({
          'api_base_url': 'https://remote-api.example.test',
          'data_api_url': 'https://remote-data.example.test/rest/v1/',
        }),
        200,
      );
    });
    final c = await BackendConfig.load(
      env: _env,
      httpClient: client,
      prefs: prefs,
    );
    expect(requested.toString(), kRemoteBackendConfigUrl);
    expect(c.apiBaseUrl, 'https://remote-api.example.test');
    expect(c.dataApiUrl, 'https://remote-data.example.test/rest/v1');
    expect(c.googleWebClientId, 'web-id');
    expect(prefs.getString(kBackendConfigCacheKey), isNotNull);
  });

  test('remote failure keeps defaults', () async {
    final prefs = await SharedPreferences.getInstance();
    for (final client in [
      MockClient((_) async => http.Response('nope', 500)),
      MockClient((_) async => throw http.ClientException('offline')),
      MockClient((_) async => http.Response('not json', 200)),
      MockClient(
        (_) async =>
            http.Response(jsonEncode({'api_base_url': 'ftp://x'}), 200),
      ),
    ]) {
      final c = await BackendConfig.load(
        env: _env,
        httpClient: client,
        prefs: prefs,
      );
      expect(c, BackendConfig.fromEnv(_env));
    }
    expect(prefs.getString(kBackendConfigCacheKey), isNull);
  });

  test('remote fetch times out and keeps defaults', () async {
    final prefs = await SharedPreferences.getInstance();
    final client = MockClient((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      return http.Response(
        jsonEncode({'api_base_url': 'https://late.example.test'}),
        200,
      );
    });
    final c = await BackendConfig.load(
      env: _env,
      httpClient: client,
      prefs: prefs,
      timeout: const Duration(milliseconds: 20),
    );
    expect(c, BackendConfig.fromEnv(_env));
  });

  test('cached remote wins on a later launch while offline', () async {
    SharedPreferences.setMockInitialValues({
      kBackendConfigCacheKey: jsonEncode({
        'api_base_url': 'https://cached-api.example.test',
        'data_api_url': 'https://cached-data.example.test/rest/v1',
      }),
    });
    final prefs = await SharedPreferences.getInstance();
    final c = await BackendConfig.load(
      env: _env,
      httpClient: MockClient((_) async => throw http.ClientException('x')),
      prefs: prefs,
    );
    expect(c.apiBaseUrl, 'https://cached-api.example.test');
    expect(c.dataApiUrl, 'https://cached-data.example.test/rest/v1');
  });
}
