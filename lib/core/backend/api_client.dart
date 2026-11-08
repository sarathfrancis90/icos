import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../services/edge_function_client.dart';
import 'backend_config.dart';
import 'token_store.dart';

/// Client for the Function's app routes (`{apiBaseUrl}/api/<name>`).
///
/// Non-2xx responses are returned as [EdgeResponse] (not thrown) so callers
/// keep classifying `code`; transport failures (no network, the 20 s
/// timeout) throw, as before. Bodies are decoded JSON when possible, the raw
/// string otherwise, null when empty.
class ApiClient {
  ApiClient(this._http, this._config, this._store);

  final http.Client _http;
  final BackendConfig _config;
  final TokenStore _store;

  static const timeout = Duration(seconds: 20);

  /// `POST /api/<name>` with the session bearer. Matches [EdgeInvoker].
  Future<EdgeResponse> invoke(String name, Map<String, dynamic> body) async {
    final response = await _http
        .post(
          _config.apiUri(name),
          headers: await _headers(authenticated: true),
          body: jsonEncode(body),
        )
        .timeout(timeout);
    return toEdgeResponse(response);
  }

  /// `GET /api/<route>`. With [public] no bearer is sent (`config`,
  /// `puzzle/<date>`).
  Future<EdgeResponse> get(String route, {bool public = false}) async {
    final response = await _http
        .get(
          _config.apiUri(route),
          headers: await _headers(authenticated: !public),
        )
        .timeout(timeout);
    return toEdgeResponse(response);
  }

  /// This client as an [EdgeInvoker].
  EdgeInvoker get invoker => invoke;

  Future<Map<String, String>> _headers({required bool authenticated}) async {
    final token = authenticated ? await _store.readSessionToken() : null;
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static EdgeResponse toEdgeResponse(http.Response response) {
    final text = response.body;
    Object? body;
    if (text.isNotEmpty) {
      try {
        body = jsonDecode(text);
      } on FormatException {
        body = text;
      }
    }
    return EdgeResponse(response.statusCode, body);
  }
}
