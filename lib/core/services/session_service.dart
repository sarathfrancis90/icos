import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../features/auth/domain/auth_outcome.dart';
import '../backend/auth_client.dart';
import '../backend/backend_providers.dart';
import '../utils/result.dart';
import 'app_logger.dart';

part 'session_service.g.dart';

/// The two things [SessionEnsurer] needs from the auth client. A seam so
/// tests never touch the network.
abstract class SessionGateway {
  bool get hasSession;

  /// Creates a guest session (throws on failure).
  Future<void> signInAnonymously();
}

class AuthClientSessionGateway implements SessionGateway {
  const AuthClientSessionGateway(this._client);

  final AuthClient _client;

  @override
  bool get hasSession => _client.currentUser != null;

  /// Asks the server about the stored session first (it may only lack the
  /// cached user), and signs in anonymously only when there is none. A
  /// failed check keeps the stored session rather than replacing it.
  @override
  Future<void> signInAnonymously() async {
    final session = await _client.getSession();
    switch (session) {
      case Failure(:final error):
        throw error;
      case Success(data: _?):
        return;
      case Success():
        final created = await _client.signInAnonymously();
        if (created case Failure(:final error)) throw error;
    }
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
    required SessionGateway gateway,
    this.signInTimeout = const Duration(seconds: 15),
  }) : _gateway = gateway;

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

/// Shared by `main()` and the providers so there is one in-flight attempt
/// per process.
@Riverpod(keepAlive: true)
SessionEnsurer sessionEnsurer(Ref ref) => SessionEnsurer(
  gateway: AuthClientSessionGateway(ref.watch(authClientProvider)),
);

/// Runs [providerFlow] (an OAuth flow for an account that already exists) and
/// then makes sure a session is still there.
///
/// The guest session is deliberately *not* signed out beforehand: the
/// `AuthClient` flows send the guest bearer and replace the session only once
/// the provider returns one, so cancelling the sheet or closing the browser
/// leaves the guest untouched. [ensureSession]
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
