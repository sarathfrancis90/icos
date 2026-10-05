import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../features/auth/domain/auth_outcome.dart';
import 'app_logger.dart';
import 'supabase_service.dart';

part 'session_service.g.dart';

/// The two things [SessionEnsurer] needs from the auth SDK. A seam so tests
/// never touch `Supabase.instance`.
abstract class SessionGateway {
  bool get hasSession;

  Future<void> signInAnonymously();
}

class SupabaseSessionGateway implements SessionGateway {
  const SupabaseSessionGateway();

  @override
  bool get hasSession => SupabaseService.auth.currentSession != null;

  @override
  Future<void> signInAnonymously() async {
    await SupabaseService.auth.signInAnonymously();
  }
}

/// Makes sure the app has a session (a guest one when nobody is signed in).
///
/// Anonymous sign-in used to be attempted once at startup; a first launch
/// offline, a revoked refresh token or a cancelled account switch left the
/// app without a session until it was killed. Everything that can fix that
/// now goes through [ensureSession].
class SessionEnsurer {
  SessionEnsurer({
    SessionGateway? gateway,
    this.signInTimeout = const Duration(seconds: 15),
  }) : _gateway = gateway ?? const SupabaseSessionGateway();

  /// Shared by `main()` and the providers so there is one in-flight attempt
  /// per process.
  static final SessionEnsurer instance = SessionEnsurer();

  final SessionGateway _gateway;

  /// A hung request must not wedge later attempts.
  final Duration signInTimeout;

  Future<bool>? _inFlight;

  bool get _hasSession {
    try {
      return _gateway.hasSession;
    } catch (_) {
      return false;
    }
  }

  /// Signs in anonymously when there is no session. Safe to call from many
  /// places at once (callers share one request), never throws, and returns
  /// whether a session exists afterwards.
  Future<bool> ensureSession() {
    if (_hasSession) return Future.value(true);
    return _inFlight ??= _signIn().whenComplete(() => _inFlight = null);
  }

  Future<bool> _signIn() async {
    try {
      await _gateway.signInAnonymously().timeout(signInTimeout);
    } catch (e, st) {
      AppLogger.debug('Anonymous sign-in failed', error: e, st: st);
    }
    return _hasSession;
  }
}

@Riverpod(keepAlive: true)
SessionEnsurer sessionEnsurer(Ref ref) => SessionEnsurer.instance;

/// Runs [providerFlow] (an OAuth flow for an account that already exists) and
/// then makes sure a session is still there.
///
/// The guest session is deliberately *not* signed out beforehand: the SDK
/// flows replace it once the provider returns a session, so cancelling the
/// sheet or closing the browser leaves the guest untouched. [ensureSession]
/// afterwards is the safety net for any path that lost the session anyway.
Future<AuthOutcome> switchToExistingAccount({
  required SessionEnsurer ensurer,
  required Future<AuthOutcome> Function() providerFlow,
}) async {
  AuthOutcome outcome;
  try {
    outcome = await providerFlow();
  } catch (e, st) {
    AppLogger.warn('Account switch failed', error: e, st: st);
    outcome = const AuthFailure('Something went wrong. Please try again.');
  }
  await ensurer.ensureSession();
  return outcome;
}
