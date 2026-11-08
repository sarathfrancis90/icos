import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../services/app_logger.dart';

/// Persists the Better Auth session token, the short-lived Data API JWT and
/// the last known user (so the app knows who is signed in while offline).
abstract interface class TokenStore {
  Future<String?> readSessionToken();
  Future<void> writeSessionToken(String token);

  /// Clears everything: session token, cached JWT and cached user.
  Future<void> clearSessionToken();

  Future<String?> cachedJwt();
  Future<DateTime?> jwtExpiry();
  Future<void> writeJwt(String jwt, DateTime expiry);
  Future<void> clearJwt();

  Future<String?> readUserJson();
  Future<void> writeUserJson(String json);
}

/// [TokenStore] on the platform keychain / keystore.
///
/// Reads never throw: a keychain / keystore failure (e.g. a key invalidated
/// by a device restore, or the keychain locked) is logged and reads as
/// "nothing stored", so startup continues as signed out and a new guest
/// session is created.
class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage])
    : _storage =
          storage ??
          const FlutterSecureStorage(
            // Readable by background fetch after the first unlock.
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock,
            ),
          );

  final FlutterSecureStorage _storage;

  static const _kSession = 'icos.session_token';
  static const _kJwt = 'icos.jwt';
  static const _kJwtExpiry = 'icos.jwt_expiry';
  static const _kUser = 'icos.user';

  Future<String?> _read(String key) async {
    try {
      return await _storage.read(key: key);
    } on Object catch (e, st) {
      // Never log the value; the key name only says which slot failed.
      AppLogger.warn(
        'secure storage read failed',
        error: e,
        st: st,
        data: {'key': key},
      );
      return null;
    }
  }

  @override
  Future<String?> readSessionToken() => _read(_kSession);

  @override
  Future<void> writeSessionToken(String token) =>
      _storage.write(key: _kSession, value: token);

  @override
  Future<void> clearSessionToken() async {
    await _storage.delete(key: _kSession);
    await _storage.delete(key: _kUser);
    await clearJwt();
  }

  @override
  Future<String?> cachedJwt() => _read(_kJwt);

  @override
  Future<DateTime?> jwtExpiry() async {
    final raw = await _read(_kJwtExpiry);
    final ms = raw == null ? null : int.tryParse(raw);
    return ms == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  }

  @override
  Future<void> writeJwt(String jwt, DateTime expiry) async {
    await _storage.write(key: _kJwt, value: jwt);
    await _storage.write(
      key: _kJwtExpiry,
      value: expiry.millisecondsSinceEpoch.toString(),
    );
  }

  @override
  Future<void> clearJwt() async {
    await _storage.delete(key: _kJwt);
    await _storage.delete(key: _kJwtExpiry);
  }

  @override
  Future<String?> readUserJson() => _read(_kUser);

  @override
  Future<void> writeUserJson(String json) =>
      _storage.write(key: _kUser, value: json);
}

/// In-memory [TokenStore] for tests.
class InMemoryTokenStore implements TokenStore {
  InMemoryTokenStore({this.sessionToken, this.jwt, this.expiry, this.userJson});

  String? sessionToken;
  String? jwt;
  DateTime? expiry;
  String? userJson;

  @override
  Future<String?> readSessionToken() async => sessionToken;

  @override
  Future<void> writeSessionToken(String token) async => sessionToken = token;

  @override
  Future<void> clearSessionToken() async {
    sessionToken = null;
    userJson = null;
    await clearJwt();
  }

  @override
  Future<String?> cachedJwt() async => jwt;

  @override
  Future<DateTime?> jwtExpiry() async => expiry;

  @override
  Future<void> writeJwt(String jwt, DateTime expiry) async {
    this.jwt = jwt;
    this.expiry = expiry;
  }

  @override
  Future<void> clearJwt() async {
    jwt = null;
    expiry = null;
  }

  @override
  Future<String?> readUserJson() async => userJson;

  @override
  Future<void> writeUserJson(String json) async => userJson = json;
}
