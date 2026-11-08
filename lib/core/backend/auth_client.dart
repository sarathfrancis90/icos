import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;

import '../constants/app_strings.dart';
import '../utils/app_error.dart';
import '../utils/result.dart';
import 'app_user.dart';
import 'auth_event.dart';
import 'backend_config.dart';
import 'token_store.dart';

/// Opens [url] in a browser session and resolves with the callback URL that
/// used [callbackUrlScheme]. Throws on cancel (PlatformException `CANCELED`).
typedef WebAuthenticator =
    Future<String> Function(Uri url, String callbackUrlScheme);

Future<String> _flutterWebAuth(Uri url, String callbackUrlScheme) =>
    FlutterWebAuth2.authenticate(
      url: url.toString(),
      callbackUrlScheme: callbackUrlScheme,
    );

/// Cookie names Better Auth uses for the session token.
const _sessionCookieNames = [
  '__Secure-better-auth.session_token',
  'better-auth.session_token',
];

/// Refresh the JWT when it has less than this left.
const kJwtRefreshMargin = Duration(seconds: 60);

const _requestTimeout = Duration(seconds: 20);

/// Better Auth client for the Neon Function (`{apiBaseUrl}/auth/*`) plus the
/// `/api/account/upgrade-email` route.
///
/// Holds the opaque session token (bearer for `/auth/*` and `/api/*`) and a
/// cached ES256 JWT (bearer for the Data API). Every method returns a
/// [Result]; transport errors become [AppError.network]. A conflict (identity
/// or email already owned by another user) is [AppError.conflict]; a
/// dismissed browser flow is [AppError.cancelled].
///
/// Call [restore] once at startup (reads the stored session, no network),
/// then [getSession] to validate it.
class AuthClient {
  AuthClient(
    this._http,
    this._config,
    this._store, {
    WebAuthenticator? webAuthenticator,
    DateTime Function()? clock,
  }) : _webAuth = webAuthenticator ?? _flutterWebAuth,
       _now = clock ?? (() => DateTime.now().toUtc());

  final http.Client _http;
  final BackendConfig _config;
  final TokenStore _store;
  final WebAuthenticator _webAuth;
  final DateTime Function() _now;

  final _events = StreamController<AuthEvent>.broadcast();
  AppUser? _currentUser;
  Future<String?>? _jwtInFlight;

  /// Broadcast auth state changes.
  Stream<AuthEvent> get events => _events.stream;

  /// The signed-in user, or null.
  AppUser? get currentUser => _currentUser;

  /// Loads the stored user (if a session token is stored) without network.
  Future<void> restore() async {
    final token = await _store.readSessionToken();
    if (token == null) {
      _currentUser = null;
      return;
    }
    final raw = await _store.readUserJson();
    if (raw == null) return;
    try {
      final json = jsonDecode(raw);
      if (json is Map<String, dynamic>) _currentUser = AppUser.fromJson(json);
    } on FormatException {
      _currentUser = null;
    }
  }

  /// Current session token, if any.
  Future<String?> sessionToken() => _store.readSessionToken();

  // ---------------------------------------------------------------------------
  // Sign-in / sign-up
  // ---------------------------------------------------------------------------

  Future<Result<AppUser, AppError>> signInAnonymously() => _signIn(
    'sign-in/anonymous',
    const <String, dynamic>{},
    providers: const [],
  );

  /// Creates an email account. When the server requires email verification
  /// no session is returned: the result is the new (unverified) user and the
  /// current session is left untouched.
  Future<Result<AppUser, AppError>> signUpEmail(
    String email,
    String password, {
    String? name,
  }) => _signIn(
    'sign-up/email',
    {'email': email, 'password': password, 'name': ?name},
    providers: const ['email'],
  );

  Future<Result<AppUser, AppError>> signInEmail(
    String email,
    String password,
  ) => _signIn(
    'sign-in/email',
    {'email': email, 'password': password},
    providers: const ['email'],
  );

  /// Native ID token sign-in (`google` | `apple`), no browser.
  Future<Result<AppUser, AppError>> signInWithIdToken({
    required String provider,
    required String idToken,
    String? nonce,
    String? accessToken,
  }) => _signIn(
    'sign-in/social',
    {
      'provider': provider,
      'idToken': _idTokenBody(idToken, nonce, accessToken),
    },
    providers: [provider],
  );

  /// Attaches a native ID token identity to the current (guest) user; the
  /// user id is kept. [AppError.conflict] when the identity belongs to
  /// another user.
  Future<Result<AppUser, AppError>> linkWithIdToken({
    required String provider,
    required String idToken,
    String? nonce,
    String? accessToken,
  }) async {
    final token = await _store.readSessionToken();
    if (token == null) {
      return const Result.failure(AppError.auth(AppStrings.backendNotSignedIn));
    }
    final sent = await _post('link-social', {
      'provider': provider,
      'idToken': _idTokenBody(idToken, nonce, accessToken),
    }, bearer: token);
    return switch (sent) {
      Failure(:final error) => Result.failure(error),
      Success(data: final r) when _ok(r) => _afterLink(r, provider),
      Success(data: final r) => Result.failure(_errorFrom(r)),
    };
  }

  /// Browser OAuth (e.g. Apple on Android). With [link] the provider is
  /// attached to the current user (`link-social`) instead of signing in.
  Future<Result<AppUser, AppError>> webOAuth(
    String provider, {
    bool link = false,
  }) async {
    final bearer = await _store.readSessionToken();
    if (link && bearer == null) {
      return const Result.failure(AppError.auth(AppStrings.backendNotSignedIn));
    }
    final sent = await _post(link ? 'link-social' : 'sign-in/social', {
      'provider': provider,
      'callbackURL': kOAuthCallbackUrl,
      'disableRedirect': true,
    }, bearer: bearer);
    final Uri authorizeUrl;
    switch (sent) {
      case Failure(:final error):
        return Result.failure(error);
      case Success(data: final r) when !_ok(r):
        return Result.failure(_errorFrom(r));
      case Success(data: final r):
        final url = _json(r.body)?['url'];
        if (url is! String || url.isEmpty) {
          return const Result.failure(
            AppError.auth(AppStrings.backendSignInFailed),
          );
        }
        final parsedUrl = Uri.tryParse(url);
        if (parsedUrl == null) {
          return const Result.failure(
            AppError.auth(AppStrings.backendSignInFailed),
          );
        }
        authorizeUrl = parsedUrl;
    }

    final proxy = _config
        .authUri('expo-authorization-proxy')
        .replace(
          queryParameters: {'authorizationURL': authorizeUrl.toString()},
        );
    final String callback;
    try {
      callback = await _webAuth(proxy, kOAuthCallbackScheme);
    } on PlatformException catch (e) {
      if (e.code == 'CANCELED' || e.code == 'CANCELLED') {
        return const Result.failure(AppError.cancelled());
      }
      return Result.failure(AppError.auth(e.message ?? e.code));
    } on Object {
      return const Result.failure(
        AppError.auth(AppStrings.backendSignInFailed),
      );
    }

    final parsed = parseOAuthCallback(callback);
    switch (parsed) {
      case Failure(:final error):
        return Result.failure(error);
      case Success(data: final sessionToken):
        final previous = _currentUser;
        // Validate the new session before replacing the stored one, so a
        // failure here leaves the current (guest) session intact.
        final session = await _fetchSession(sessionToken);
        switch (session) {
          case Failure(:final error):
            return Result.failure(error);
          case Success(data: null):
            return const Result.failure(
              AppError.auth(AppStrings.backendSignInFailed),
            );
          case Success(data: final AppUser user):
            await _store.writeSessionToken(sessionToken);
            await _resetJwt();
            final merged = user.copyWith(
              providers: {...user.providers, provider}.toList(),
            );
            await _setUser(merged);
            _emit(
              link && previous?.id == merged.id
                  ? AuthEvent.userUpdated
                  : AuthEvent.signedIn,
            );
            return Result.success(merged);
        }
    }
  }

  /// Parses `io.icos://oauth-callback?cookie=<Set-Cookie>` into the session
  /// token, or `?error=...` into an [AppError.auth].
  static Result<String, AppError> parseOAuthCallback(String callbackUrl) {
    // Never throws: malformed percent-encoding is a failed sign-in.
    try {
      return _parseOAuthCallback(callbackUrl);
    } on Object {
      return const Result.failure(
        AppError.auth(AppStrings.backendSignInFailed),
      );
    }
  }

  static Result<String, AppError> _parseOAuthCallback(String callbackUrl) {
    final uri = Uri.tryParse(callbackUrl);
    if (uri == null) {
      return const Result.failure(
        AppError.auth(AppStrings.backendSignInFailed),
      );
    }
    final params = uri.queryParameters;
    final error = params['error'];
    if (error != null && error.isNotEmpty) {
      return Result.failure(AppError.auth(error));
    }
    final cookie = params['cookie'];
    if (cookie != null) {
      for (final name in _sessionCookieNames) {
        final match = RegExp(
          '(?:^|[;,\\s])${RegExp.escape(name)}=([^;,]*)',
        ).firstMatch(cookie);
        final raw = match?.group(1)?.trim();
        if (raw != null && raw.isNotEmpty) {
          return Result.success(Uri.decodeComponent(raw));
        }
      }
    }
    return const Result.failure(AppError.auth(AppStrings.backendSignInFailed));
  }

  /// Converts the current guest into an email account in place
  /// (`/api/account/upgrade-email`). 409 `EMAIL_EXISTS` is a conflict.
  Future<Result<AppUser, AppError>> upgradeEmail(
    String email,
    String password,
  ) async {
    final token = await _store.readSessionToken();
    if (token == null) {
      return const Result.failure(AppError.auth(AppStrings.backendNotSignedIn));
    }
    final sent = await _send(
      () => _http.post(
        _config.apiUri('account/upgrade-email'),
        headers: _headers(token),
        body: jsonEncode({'email': email, 'password': password}),
      ),
    );
    switch (sent) {
      case Failure(:final error):
        return Result.failure(error);
      case Success(data: final r) when !_ok(r):
        return Result.failure(_errorFrom(r));
      case Success(data: final r):
        await _captureRotatedToken(r);
        final userJson = _json(r.body)?['user'];
        if (userJson is! Map<String, dynamic>) {
          return const Result.failure(
            AppError.unknown(AppStrings.errorGeneric),
          );
        }
        final user = AppUser.fromJson(
          userJson,
          providers: {...?_currentUser?.providers, 'email'}.toList(),
        );
        await _resetJwt();
        await _setUser(user);
        _emit(AuthEvent.userUpdated);
        return Result.success(user);
    }
  }

  // ---------------------------------------------------------------------------
  // Session
  // ---------------------------------------------------------------------------

  /// Validates the stored session with the server. Success(null) when there
  /// is no (longer a) session; a dead session is cleared and emits
  /// [AuthEvent.signedOut]. Network failures keep the stored session.
  Future<Result<AppUser?, AppError>> getSession() async {
    final token = await _store.readSessionToken();
    if (token == null) {
      _currentUser = null;
      return const Result.success(null);
    }
    final previous = _currentUser;
    final session = await _fetchSession(token);
    switch (session) {
      case Failure(:final error):
        return Result.failure(error);
      case Success(data: null):
        await _clearLocal(emit: previous != null);
        return const Result.success(null);
      case Success(data: final AppUser user):
        await _setUser(user);
        if (previous == null) {
          _emit(AuthEvent.signedIn);
        } else if (previous != user) {
          _emit(AuthEvent.userUpdated);
        }
        return Result.success(user);
    }
  }

  /// A JWT for the Data API, refreshed via `GET /auth/token` when it has
  /// less than [kJwtRefreshMargin] left (or always with [force]). Null when
  /// signed out or when no JWT can be obtained (offline with an expired
  /// cache). A 401 from `/auth/token` means the session is gone: it is
  /// cleared and [AuthEvent.signedOut] emitted.
  Future<String?> freshJwt({bool force = false}) async {
    if (!force) {
      final cached = await _store.cachedJwt();
      final expiry = await _store.jwtExpiry();
      if (cached != null &&
          expiry != null &&
          expiry.difference(_now()) > kJwtRefreshMargin) {
        return cached;
      }
    }
    final inFlight = _jwtInFlight;
    if (inFlight != null) return inFlight;
    late final Future<String?> refresh;
    refresh = _refreshJwt().whenComplete(() {
      if (identical(_jwtInFlight, refresh)) _jwtInFlight = null;
    });
    return _jwtInFlight = refresh;
  }

  Future<String?> _refreshJwt() async {
    final token = await _store.readSessionToken();
    if (token == null) return null;
    final sent = await _send(
      () => _http.get(_config.authUri('token'), headers: _headers(token)),
    );
    // A sign-out / new sign-in while the call was in flight makes this
    // response stale: never write the old account's JWT or token back.
    if (await _store.readSessionToken() != token) return null;
    switch (sent) {
      case Failure():
        return _usableCachedJwt();
      case Success(data: final r) when r.statusCode == 401:
        await _clearLocal(emit: true);
        return null;
      case Success(data: final r) when !_ok(r):
        return _usableCachedJwt();
      case Success(data: final r):
        await _captureRotatedToken(r, sentWith: token);
        final jwt = _json(r.body)?['token'];
        if (jwt is! String || jwt.isEmpty) return _usableCachedJwt();
        await _store.writeJwt(jwt, _jwtExpiry(jwt));
        return jwt;
    }
  }

  Future<String?> _usableCachedJwt() async {
    final cached = await _store.cachedJwt();
    final expiry = await _store.jwtExpiry();
    if (cached != null && expiry != null && expiry.isAfter(_now())) {
      return cached;
    }
    return null;
  }

  DateTime _jwtExpiry(String jwt) {
    final parts = jwt.split('.');
    if (parts.length == 3) {
      try {
        final payload = jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
        );
        if (payload is Map<String, dynamic>) {
          final exp = payload['exp'];
          if (exp is num) {
            return DateTime.fromMillisecondsSinceEpoch(
              (exp * 1000).toInt(),
              isUtc: true,
            );
          }
        }
      } on FormatException {
        // Fall through to the default lifetime.
      }
    }
    return _now().add(const Duration(minutes: 15));
  }

  /// Signs out on the server (best effort) and always clears local state.
  Future<Result<void, AppError>> signOut() async {
    final token = await _store.readSessionToken();
    if (token != null) {
      await _post('sign-out', const <String, dynamic>{}, bearer: token);
    }
    await _clearLocal(emit: true);
    return const Result.success(null);
  }

  // ---------------------------------------------------------------------------
  // Password / verification
  // ---------------------------------------------------------------------------

  Future<Result<void, AppError>> requestPasswordReset(
    String email, {
    String? redirectTo,
  }) => _postVoid('request-password-reset', {
    'email': email,
    'redirectTo': ?redirectTo,
  });

  Future<Result<void, AppError>> resetPassword(
    String token,
    String newPassword,
  ) =>
      _postVoid('reset-password', {'newPassword': newPassword, 'token': token});

  /// Sends a verification email to [email], or to the current user's address
  /// (e.g. resending after a sign-up that returned no session).
  Future<Result<void, AppError>> sendVerificationEmail({
    String? email,
    String? callbackURL,
  }) async {
    final address = email ?? _currentUser?.email;
    if (address == null || address.isEmpty) {
      return const Result.failure(
        AppError.validation(AppStrings.backendNoEmail),
      );
    }
    return _postVoid('send-verification-email', {
      'email': address,
      'callbackURL': ?callbackURL,
    });
  }

  /// Emits [AuthEvent.passwordRecovery] (called when a reset link opens the
  /// app, so the router can show the new-password screen).
  void notifyPasswordRecovery() => _emit(AuthEvent.passwordRecovery);

  Future<void> dispose() => _events.close();

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  Future<Result<AppUser, AppError>> _signIn(
    String path,
    Map<String, dynamic> body, {
    required List<String> providers,
  }) async {
    // The server uses the guest's bearer to re-key or discard the guest.
    final guest = await _store.readSessionToken();
    final sent = await _post(path, body, bearer: guest);
    switch (sent) {
      case Failure(:final error):
        return Result.failure(error);
      case Success(data: final r) when !_ok(r):
        return Result.failure(_errorFrom(r));
      case Success(data: final r):
        final json = _json(r.body);
        final userJson = json?['user'];
        if (userJson is! Map<String, dynamic>) {
          return const Result.failure(
            AppError.auth(AppStrings.backendSignInFailed),
          );
        }
        final user = AppUser.fromJson(userJson, providers: providers);
        final headerToken = r.headers['set-auth-token'];
        final bodyToken = json?['token'];
        final token = headerToken != null && headerToken.isNotEmpty
            ? headerToken
            : (bodyToken is String && bodyToken.isNotEmpty ? bodyToken : null);
        if (token == null) return Result.success(user);
        await _store.writeSessionToken(token);
        await _resetJwt();
        await _setUser(user);
        _emit(AuthEvent.signedIn);
        return Result.success(user);
    }
  }

  Future<Result<AppUser, AppError>> _afterLink(
    http.Response r,
    String provider,
  ) async {
    await _captureRotatedToken(r);
    await _resetJwt();
    final token = await _store.readSessionToken();
    if (token == null) {
      return const Result.failure(AppError.auth(AppStrings.backendNotSignedIn));
    }
    final session = await _fetchSession(token);
    switch (session) {
      case Failure(:final error):
        return Result.failure(error);
      case Success(data: null):
        await _clearLocal(emit: true);
        return const Result.failure(
          AppError.auth(AppStrings.backendNotSignedIn),
        );
      case Success(data: final AppUser user):
        final merged = user.copyWith(
          providers: {...user.providers, provider}.toList(),
        );
        await _setUser(merged);
        _emit(AuthEvent.userUpdated);
        return Result.success(merged);
    }
  }

  /// `GET get-session` (+ best-effort `list-accounts` for providers).
  /// Success(null) when the server says there is no session.
  Future<Result<AppUser?, AppError>> _fetchSession(String token) async {
    final sent = await _send(
      () => _http.get(_config.authUri('get-session'), headers: _headers(token)),
    );
    switch (sent) {
      case Failure(:final error):
        return Result.failure(error);
      case Success(data: final r) when r.statusCode == 401:
        return const Result.success(null);
      case Success(data: final r) when !_ok(r):
        return Result.failure(_errorFrom(r));
      case Success(data: final r):
        await _captureRotatedToken(r, sentWith: token);
        final userJson = _json(r.body)?['user'];
        if (userJson is! Map<String, dynamic>) {
          return const Result.success(null);
        }
        final providers = await _listProviders(token);
        return Result.success(
          AppUser.fromJson(
            userJson,
            providers: providers ?? _currentUser?.providers ?? const [],
          ),
        );
    }
  }

  Future<List<String>?> _listProviders(String token) async {
    final sent = await _send(
      () =>
          _http.get(_config.authUri('list-accounts'), headers: _headers(token)),
    );
    if (sent case Success(data: final r) when _ok(r)) {
      final decoded = _decode(r.body);
      if (decoded is List) {
        return {
          for (final a in decoded.whereType<Map<String, dynamic>>())
            if (a['providerId'] case final String id when id != 'anonymous')
              id == 'credential' ? 'email' : id,
        }.toList();
      }
    }
    return null;
  }

  Future<Result<void, AppError>> _postVoid(
    String path,
    Map<String, dynamic> body,
  ) async {
    final sent = await _post(
      path,
      body,
      bearer: await _store.readSessionToken(),
    );
    return switch (sent) {
      Failure(:final error) => Result.failure(error),
      Success(data: final r) when _ok(r) => const Result.success(null),
      Success(data: final r) => Result.failure(_errorFrom(r)),
    };
  }

  Future<Result<http.Response, AppError>> _post(
    String path,
    Map<String, dynamic> body, {
    String? bearer,
  }) => _send(
    () => _http.post(
      _config.authUri(path),
      headers: _headers(bearer),
      body: jsonEncode(body),
    ),
  );

  Future<Result<http.Response, AppError>> _send(
    Future<http.Response> Function() request,
  ) async {
    try {
      return Result.success(await request().timeout(_requestTimeout));
    } on TimeoutException {
      return const Result.failure(AppError.network(AppStrings.errorTimeout));
    } on SocketException {
      return const Result.failure(AppError.network(AppStrings.errorNetwork));
    } on http.ClientException {
      return const Result.failure(AppError.network(AppStrings.errorNetwork));
    }
  }

  Map<String, String> _headers(String? bearer) => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    if (bearer != null) 'Authorization': 'Bearer $bearer',
  };

  /// Adopts a rotated session token (`set-auth-token` on any response).
  /// With [sentWith], only when that token is the stored one (so validating
  /// a not-yet-adopted session never overwrites the current one).
  Future<void> _captureRotatedToken(http.Response r, {String? sentWith}) async {
    final rotated = r.headers['set-auth-token'];
    if (rotated == null || rotated.isEmpty) return;
    if (sentWith != null && await _store.readSessionToken() != sentWith) {
      return;
    }
    await _store.writeSessionToken(rotated);
  }

  Future<void> _setUser(AppUser user) async {
    _currentUser = user;
    await _store.writeUserJson(jsonEncode(user.toJson()));
  }

  /// Drops the cached JWT and detaches any in-flight refresh (it belongs
  /// to the previous session; its result is discarded).
  Future<void> _resetJwt() async {
    _jwtInFlight = null;
    await _store.clearJwt();
  }

  Future<void> _clearLocal({required bool emit}) async {
    _jwtInFlight = null;
    await _store.clearSessionToken();
    _currentUser = null;
    if (emit) _emit(AuthEvent.signedOut);
  }

  void _emit(AuthEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  static Map<String, dynamic> _idTokenBody(
    String token,
    String? nonce,
    String? accessToken,
  ) => {'token': token, 'nonce': ?nonce, 'accessToken': ?accessToken};

  static bool _ok(http.Response r) => r.statusCode >= 200 && r.statusCode < 300;

  static Object? _decode(String body) {
    if (body.isEmpty) return null;
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }

  static Map<String, dynamic>? _json(String body) {
    final decoded = _decode(body);
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  static const _conflictCodes = {
    'EMAIL_EXISTS',
    'USER_ALREADY_EXISTS',
    'USER_ALREADY_EXISTS_USE_ANOTHER_EMAIL',
    'ACCOUNT_ALREADY_LINKED',
    'SOCIAL_ACCOUNT_ALREADY_LINKED',
    'ACCOUNT_ALREADY_LINKED_TO_DIFFERENT_USER',
  };

  /// Maps a non-2xx Better Auth (`{code, message}`) or app route
  /// (`{error, code}`) response to an [AppError].
  static AppError _errorFrom(http.Response r) {
    final json = _json(r.body);
    final code = json?['code'] is String ? json!['code'] as String : '';
    final rawMessage = json?['message'] ?? json?['error'];
    final message = rawMessage is String && rawMessage.isNotEmpty
        ? rawMessage
        : AppStrings.errorGeneric;
    final upper = code.toUpperCase();
    if (r.statusCode == 409 ||
        _conflictCodes.contains(upper) ||
        upper.contains('ALREADY_LINKED')) {
      return AppError.conflict(
        rawMessage is String && rawMessage.isNotEmpty
            ? rawMessage
            : AppStrings.backendIdentityExists,
      );
    }
    return switch (r.statusCode) {
      401 || 403 => AppError.auth(message),
      404 => AppError.notFound(message),
      429 => AppError.rateLimit(message),
      400 || 422 => AppError.validation(message),
      _ => AppError.unknown(message),
    };
  }
}
