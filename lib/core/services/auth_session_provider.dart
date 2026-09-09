import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'supabase_service.dart';

part 'auth_session_provider.g.dart';

/// Minimal view of the auth session used by sync / result providers.
/// Overridable in tests so they never touch `Supabase.instance`.
abstract class AuthSessionInfo {
  const AuthSessionInfo();

  bool get hasSession;
  String? get userId;
}

class SupabaseAuthSessionInfo extends AuthSessionInfo {
  const SupabaseAuthSessionInfo();

  @override
  bool get hasSession => SupabaseService.auth.currentSession != null;

  @override
  String? get userId => SupabaseService.auth.currentUser?.id;
}

/// Fixed session info for tests.
class FakeAuthSessionInfo extends AuthSessionInfo {
  const FakeAuthSessionInfo({this.userId = 'test-user', this.hasSession = true});

  @override
  final bool hasSession;

  @override
  final String? userId;
}

@Riverpod(keepAlive: true)
AuthSessionInfo authSession(Ref ref) => const SupabaseAuthSessionInfo();
