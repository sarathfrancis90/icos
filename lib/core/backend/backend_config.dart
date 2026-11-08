import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Deep-link scheme the browser OAuth flow returns to.
const kOAuthCallbackScheme = 'io.icos';

/// Callback URL handed to the Function for the browser OAuth flow.
const kOAuthCallbackUrl = 'io.icos://oauth-callback';

/// Remote override for the backend hosts, so a changed Neon host can be fixed
/// without a store release. This host is trusted: it can route all traffic.
const kRemoteBackendConfigUrl = 'https://icos.sarathfrancis.work/config.json';

/// SharedPreferences key holding the last good remote override (raw JSON).
const kBackendConfigCacheKey = 'backend_config_json';

/// Upper bound for the remote override fetch.
const kRemoteBackendConfigTimeout = Duration(seconds: 5);

/// Hosts and client ids the app talks to.
///
/// [apiBaseUrl] is the Neon Function origin (no trailing slash): Better Auth
/// lives under `/auth/`, app routes under `/api/`. [dataApiUrl] is the Neon
/// Data API (PostgREST) root, e.g. `.../neondb/rest/v1` (no trailing slash).
@immutable
class BackendConfig {
  BackendConfig({
    required String apiBaseUrl,
    required String dataApiUrl,
    this.googleWebClientId = '',
    this.googleIosClientId = '',
    this.appleServiceId = '',
  }) : apiBaseUrl = _trimSlash(apiBaseUrl),
       dataApiUrl = _trimSlash(dataApiUrl);

  /// Compiled defaults from the dotenv map.
  factory BackendConfig.fromEnv(Map<String, String> env) => BackendConfig(
    apiBaseUrl: env['API_BASE_URL'] ?? '',
    dataApiUrl: env['DATA_API_URL'] ?? '',
    googleWebClientId: env['GOOGLE_WEB_CLIENT_ID'] ?? '',
    googleIosClientId: env['GOOGLE_IOS_CLIENT_ID'] ?? '',
    appleServiceId: env['APPLE_SERVICE_ID'] ?? '',
  );

  final String apiBaseUrl;
  final String dataApiUrl;
  final String googleWebClientId;
  final String googleIosClientId;
  final String appleServiceId;

  bool get isConfigured => apiBaseUrl.isNotEmpty && dataApiUrl.isNotEmpty;

  /// `{apiBaseUrl}/auth/<path>` (Better Auth).
  Uri authUri(String path) => Uri.parse('$apiBaseUrl/auth/$path');

  /// `{apiBaseUrl}/api/<route>` (app routes).
  Uri apiUri(String route) => Uri.parse('$apiBaseUrl/api/$route');

  /// Applies a remote override (`{api_base_url, data_api_url}`); invalid or
  /// missing values keep the current ones.
  BackendConfig withRemote(Map<String, dynamic> json) {
    final api = _validUrl(json['api_base_url']);
    final data = _validUrl(json['data_api_url']);
    return BackendConfig(
      apiBaseUrl: api ?? apiBaseUrl,
      dataApiUrl: data ?? dataApiUrl,
      googleWebClientId: googleWebClientId,
      googleIosClientId: googleIosClientId,
      appleServiceId: appleServiceId,
    );
  }

  /// Resolves the config for this launch.
  ///
  /// Starts from the dotenv defaults. When a remote override was cached on an
  /// earlier launch it wins immediately and the remote file is re-fetched in
  /// the background for the next launch (no startup wait). With no cache the
  /// remote file is awaited (at most [timeout]); any failure keeps the
  /// defaults. Never throws.
  static Future<BackendConfig> load({
    Map<String, String>? env,
    http.Client? httpClient,
    SharedPreferences? prefs,
    Uri? remoteUrl,
    Duration timeout = kRemoteBackendConfigTimeout,
  }) async {
    final defaults = BackendConfig.fromEnv(env ?? _dotenv());
    final store = prefs ?? await SharedPreferences.getInstance();
    final cached = _decode(store.getString(kBackendConfigCacheKey));
    final fetch = fetchRemote(
      store,
      httpClient: httpClient,
      remoteUrl: remoteUrl,
      timeout: timeout,
    );
    if (cached != null) {
      unawaited(fetch);
      return defaults.withRemote(cached);
    }
    final remote = await fetch;
    return remote == null ? defaults : defaults.withRemote(remote);
  }

  /// Fetches the remote override and caches it when valid. Returns the
  /// decoded JSON, or null on any failure. Never throws.
  static Future<Map<String, dynamic>?> fetchRemote(
    SharedPreferences prefs, {
    http.Client? httpClient,
    Uri? remoteUrl,
    Duration timeout = kRemoteBackendConfigTimeout,
  }) async {
    final client = httpClient ?? http.Client();
    try {
      final response = await client
          .get(remoteUrl ?? Uri.parse(kRemoteBackendConfigUrl))
          .timeout(timeout);
      if (response.statusCode != 200) return null;
      final json = _decode(response.body);
      if (json == null) return null;
      if (_validUrl(json['api_base_url']) == null &&
          _validUrl(json['data_api_url']) == null) {
        return null;
      }
      await prefs.setString(kBackendConfigCacheKey, jsonEncode(json));
      return json;
    } on Object {
      return null;
    } finally {
      if (httpClient == null) client.close();
    }
  }

  static Map<String, String> _dotenv() =>
      dotenv.isInitialized ? dotenv.env : const <String, String>{};

  static Map<String, dynamic>? _decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  static String? _validUrl(Object? value) {
    if (value is! String || value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
    return value;
  }

  static String _trimSlash(String url) {
    var out = url.trim();
    while (out.endsWith('/')) {
      out = out.substring(0, out.length - 1);
    }
    return out;
  }

  @override
  bool operator ==(Object other) =>
      other is BackendConfig &&
      other.apiBaseUrl == apiBaseUrl &&
      other.dataApiUrl == dataApiUrl &&
      other.googleWebClientId == googleWebClientId &&
      other.googleIosClientId == googleIosClientId &&
      other.appleServiceId == appleServiceId;

  @override
  int get hashCode => Object.hash(
    apiBaseUrl,
    dataApiUrl,
    googleWebClientId,
    googleIosClientId,
    appleServiceId,
  );
}
