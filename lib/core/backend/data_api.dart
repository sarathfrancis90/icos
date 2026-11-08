import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:postgrest/postgrest.dart';

import 'auth_client.dart';
import 'backend_config.dart';

/// Neon Data API (PostgREST) client.
///
/// Every request carries `Authorization: Bearer <JWT>` from
/// [AuthClient.freshJwt] (refreshed when < 60 s left). The Data API answers
/// a missing / expired JWT with **400** (message mentions JWT / token), so a
/// 400 or 401 whose body mentions a JWT triggers one forced refresh and one
/// retry. With no session no header is sent (the request then fails on the
/// server; the app always holds at least a guest session).
///
/// Query shapes are standard PostgREST via [client] / [from] / [rpc];
/// errors surface as [PostgrestException] (SQL code in `code`, HINT in
/// `hint`).
class DataApi {
  DataApi(BackendConfig config, AuthClient auth, {http.Client? httpClient})
    : this._(config, JwtHttpClient(httpClient ?? http.Client(), auth.freshJwt));

  DataApi._(BackendConfig config, this._http)
    : client = PostgrestClient(config.dataApiUrl, httpClient: _http);

  final JwtHttpClient _http;

  /// The underlying PostgREST client (JWT injected per request).
  final PostgrestClient client;

  PostgrestQueryBuilder<void> from(String table) => client.from(table);

  PostgrestFilterBuilder<T> rpc<T>(
    String fn, {
    Map<String, dynamic>? params,
    bool get = false,
  }) => client.rpc<T>(fn, params: params, get: get);

  Future<void> dispose() async {
    await client.dispose();
    _http.close();
  }
}

/// Lazily resolves the Data API client. Repositories take this instead of
/// a [PostgrestClient] so building them never touches the backend
/// providers; a missing configuration then fails inside the call (and is
/// mapped to an `AppError`) rather than when the repository is created.
typedef PostgrestClientGetter = PostgrestClient Function();

/// Returns a JWT (forced refresh when [force]) or null when signed out.
typedef JwtProvider = Future<String?> Function({bool force});

/// [http.BaseClient] that injects the Data API JWT and retries once after a
/// forced refresh when the server rejects the token.
class JwtHttpClient extends http.BaseClient {
  JwtHttpClient(this._inner, this._jwt);

  final http.Client _inner;
  final JwtProvider _jwt;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final jwt = await _jwt();
    if (request is! http.Request) {
      // Streamed / multipart bodies cannot be replayed: send once.
      _authorize(request, jwt);
      return _withRequest(await _inner.send(request), request);
    }

    final firstRequest = _copy(request, jwt);
    final first = _withRequest(await _inner.send(firstRequest), firstRequest);
    if (jwt == null || (first.statusCode != 400 && first.statusCode != 401)) {
      return first;
    }
    final buffered = await http.Response.fromStream(first);
    if (!_mentionsJwt(buffered.body)) return _restream(buffered, firstRequest);

    final refreshed = await _jwt(force: true);
    if (refreshed == null) return _restream(buffered, firstRequest);
    final retry = _copy(request, refreshed);
    return _withRequest(await _inner.send(retry), retry);
  }

  /// PostgREST reads `response.request`; some clients (mocks) leave it null.
  static http.StreamedResponse _withRequest(
    http.StreamedResponse r,
    http.BaseRequest request,
  ) => r.request != null
      ? r
      : http.StreamedResponse(
          r.stream,
          r.statusCode,
          contentLength: r.contentLength,
          request: request,
          headers: r.headers,
          reasonPhrase: r.reasonPhrase,
          isRedirect: r.isRedirect,
          persistentConnection: r.persistentConnection,
        );

  @override
  void close() => _inner.close();

  /// PostgREST JWT errors: the message mentions "JWT" or the code is
  /// `PGRST30x` (PGRST300-PGRST303).
  static final _jwtError = RegExp(r'jwt|PGRST30\d', caseSensitive: false);

  static bool _mentionsJwt(String body) => _jwtError.hasMatch(body);

  static void _authorize(http.BaseRequest request, String? jwt) {
    request.headers.removeWhere((k, _) => k.toLowerCase() == 'authorization');
    if (jwt != null) request.headers['Authorization'] = 'Bearer $jwt';
  }

  static http.Request _copy(http.Request source, String? jwt) {
    final copy = http.Request(source.method, source.url)
      ..followRedirects = source.followRedirects
      ..maxRedirects = source.maxRedirects
      ..persistentConnection = source.persistentConnection
      ..headers.addAll(source.headers)
      ..bodyBytes = source.bodyBytes;
    // Setting bodyBytes may add a default content-type; keep the source's.
    final type =
        source.headers['content-type'] ?? source.headers['Content-Type'];
    if (type != null) copy.headers['content-type'] = type;
    _authorize(copy, jwt);
    return copy;
  }

  static http.StreamedResponse _restream(
    http.Response r,
    http.BaseRequest request,
  ) => http.StreamedResponse(
    Stream.value(r.bodyBytes),
    r.statusCode,
    contentLength: r.bodyBytes.length,
    request: r.request ?? request,
    headers: r.headers,
    reasonPhrase: r.reasonPhrase,
    isRedirect: r.isRedirect,
    persistentConnection: r.persistentConnection,
  );
}
