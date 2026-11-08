import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../backend/auth_client.dart';
import '../backend/backend_providers.dart';

part 'auth_session_provider.g.dart';

/// Minimal view of the auth session used by sync / result providers.
/// Overridable in tests so they never touch the network.
abstract class AuthSessionInfo {
  const AuthSessionInfo();

  bool get hasSession;
  String? get userId;
}

/// Reads [AuthClient.currentUser] on every access (never cached).
class AuthClientSessionInfo extends AuthSessionInfo {
  const AuthClientSessionInfo(this._client);

  final AuthClient _client;

  @override
  bool get hasSession => _client.currentUser != null;

  @override
  String? get userId => _client.currentUser?.id;
}

/// Fixed session info for tests.
class FakeAuthSessionInfo extends AuthSessionInfo {
  const FakeAuthSessionInfo({
    this.userId = 'test-user',
    this.hasSession = true,
  });

  @override
  final bool hasSession;

  @override
  final String? userId;
}

@Riverpod(keepAlive: true)
AuthSessionInfo authSession(Ref ref) =>
    AuthClientSessionInfo(ref.watch(authClientProvider));
