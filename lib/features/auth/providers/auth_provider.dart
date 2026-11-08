import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../../core/backend/app_user.dart';
import '../../../core/backend/auth_client.dart';
import '../../../core/backend/auth_event.dart';
import '../../../core/backend/backend_config.dart';
import '../../../core/backend/backend_providers.dart';
import '../../../core/router/invite_continuation.dart';
import '../../../core/services/analytics_service.dart';
import '../../../core/services/app_logger.dart';
import '../../../core/services/session_service.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/utils/app_error.dart';
import '../../../core/utils/result.dart';
import '../../groups/domain/pending_invite.dart';
import '../data/native_sign_in.dart';
import '../domain/auth_outcome.dart';
import '../domain/auth_strategy.dart';

export '../../../core/backend/app_user.dart' show AppUser;
export '../../../core/backend/auth_event.dart' show AuthEvent;
export '../domain/auth_outcome.dart';
export '../domain/auth_strategy.dart' show OAuthKind;

part 'auth_provider.g.dart';

/// One auth state change: what happened and the user afterwards (null once
/// signed out).
@immutable
class AuthStateChange {
  const AuthStateChange(this.event, [this.user]);

  final AuthEvent event;
  final AppUser? user;
}

/// One-shot user-facing messages produced by asynchronous auth events.
/// Screens `ref.listen` to this, show a SnackBar and call
/// [AuthFlowMessage.clear].
@riverpod
class AuthFlowMessage extends _$AuthFlowMessage {
  @override
  String? build() => null;

  void show(String message) => state = message;

  void clear() => state = null;
}

/// One-shot signal that an asynchronous sign-in came back with "this
/// identity already belongs to another account".
///
/// Kept separate from [AuthFlowMessage] because this one is not a message. It
/// needs an action: offer to sign in to that account instead. Every current
/// flow returns [AuthIdentityExists] directly; this stays for screens that
/// listen for a late report.
@riverpod
class AuthIdentityConflict extends _$AuthIdentityConflict {
  @override
  OAuthKind? build() => null;

  void show(OAuthKind? provider) => state = provider;

  void clear() => state = null;
}

/// Set when a password-reset link was opened before the app's providers
/// existed, so the recovery screen is still shown. [token] is the reset
/// token from the link (`/reset?token=…`).
abstract final class PasswordRecoveryLatch {
  static bool arrivedBeforeStart = false;
  static String? token;

  /// Records a reset link's [resetToken] that arrived before startup.
  static void arrive(String resetToken) {
    token = resetToken;
    arrivedBeforeStart = true;
  }
}

/// True when the player is a guest with progress on this device while a
/// password reset is under way: signing in to the account afterwards
/// replaces the guest, so the "set a new password" screen warns that this
/// progress will not carry over.
@Riverpod(keepAlive: true)
class RecoveryReplacesGuest extends _$RecoveryReplacesGuest {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

/// True from the moment a password-reset link opens the app until the
/// player sets a new password (or dismisses the screen). The router sends
/// the player to the "set a new password" screen while this is true; [token]
/// is the reset token the new password is sent with.
@Riverpod(keepAlive: true)
class PasswordRecoveryPending extends _$PasswordRecoveryPending {
  /// The guest session active before the link, if any.
  String? _guestId;
  String? _token;

  /// The reset token from the link, or null when none arrived.
  String? get token => _token;

  @override
  bool build() {
    final current = ref.read(authNotifierProvider).valueOrNull;
    if (current != null && current.isAnonymous) _guestId = current.id;

    ref.listen<AsyncValue<AuthStateChange>>(authStateChangesProvider, (
      _,
      next,
    ) {
      final data = next.valueOrNull;
      if (data == null) return;
      final user = data.user;
      if (data.event == AuthEvent.passwordRecovery) {
        if (user != null && user.isAnonymous) _guestId = user.id;
        _begin(PasswordRecoveryLatch.token ?? _token);
      } else if (user != null && user.isAnonymous) {
        _guestId = user.id;
      } else if (data.event == AuthEvent.signedOut) {
        _guestId = null;
      }
    });
    final early = PasswordRecoveryLatch.arrivedBeforeStart;
    PasswordRecoveryLatch.arrivedBeforeStart = false;
    if (early) _token = PasswordRecoveryLatch.token;
    return early;
  }

  /// A reset link with [resetToken] was opened.
  void start(String resetToken) => _begin(resetToken);

  void _begin(String? resetToken) {
    _token = resetToken;
    PasswordRecoveryLatch.token = null;
    final guest = _guestId;
    ref
        .read(recoveryReplacesGuestProvider.notifier)
        .set(guest != null && StorageService.hasLocalProgress(guest));
    state = true;
  }

  /// Recovery finished (password set) or was dismissed.
  void clear() {
    PasswordRecoveryLatch.arrivedBeforeStart = false;
    PasswordRecoveryLatch.token = null;
    _token = null;
    ref.read(recoveryReplacesGuestProvider.notifier).set(false);
    state = false;
  }
}

class _ResumeObserver with WidgetsBindingObserver {
  _ResumeObserver(this._onResumed);
  final void Function() _onResumed;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _onResumed();
  }
}

@riverpod
class AuthNotifier extends _$AuthNotifier {
  StreamSubscription<AuthEvent>? _subscription;

  /// True only while the browser sheet/tab is showing; reset on every way
  /// out of [_launchWeb].
  bool _webFlowOpen = false;

  /// Sign-in/link calls running now, and when the last one ended. Their own
  /// outcome announces the result, so the auth events they cause (delivered
  /// during the call or a tick later) must not announce it again.
  int _flowsRunning = 0;
  DateTime? _flowEndedAt;

  bool get _flowInProgress {
    if (_flowsRunning > 0) return true;
    final at = _flowEndedAt;
    return at != null &&
        DateTime.now().difference(at) < const Duration(seconds: 3);
  }

  Timer? _resumeTimer;

  /// How long a resume must leave the busy state untouched before it is
  /// treated as stuck; a resume with the sheet still up is not abandonment.
  @visibleForTesting
  static Duration resumeGrace = const Duration(seconds: 1);

  late final _ResumeObserver _resumeObserver = _ResumeObserver(
    handleAppResumed,
  );

  AuthClient get _client => ref.read(authClientProvider);

  @override
  AsyncValue<AppUser?> build() {
    attachLifecycleObserver();
    final client = _client;
    _subscription?.cancel();
    _subscription = client.events.listen(
      (event) => handleAuthEvent(AuthStateChange(event, client.currentUser)),
    );
    ref.onDispose(() => _subscription?.cancel());
    return AsyncValue.data(client.currentUser);
  }

  /// Starts listening for the app returning to the foreground; removed again
  /// when the provider is disposed. Public so test fakes that override
  /// [build] can opt in.
  @visibleForTesting
  void attachLifecycleObserver() {
    WidgetsFlutterBinding.ensureInitialized();
    WidgetsBinding.instance.addObserver(_resumeObserver);
    ref.onDispose(() {
      _resumeTimer?.cancel();
      WidgetsBinding.instance.removeObserver(_resumeObserver);
    });
  }

  /// Handles an auth event. Public only so tests can drive it.
  @visibleForTesting
  void handleAuthEvent(AuthStateChange data) {
    final previous = state.valueOrNull;
    final user =
        data.user ?? (data.event == AuthEvent.signedOut ? null : currentUser);
    state = AsyncValue.data(user);
    final signedInOrUpdated =
        data.event == AuthEvent.userUpdated || data.event == AuthEvent.signedIn;
    if (signedInOrUpdated) unawaited(AnalyticsService.setUserId(user?.id));
    if (data.event == AuthEvent.userUpdated &&
        user != null &&
        !user.isAnonymous &&
        previous != null &&
        previous.isAnonymous &&
        previous.id == user.id &&
        !_flowInProgress) {
      // A guest became an account outside a flow that reports it itself.
      ref
          .read(authFlowMessageProvider.notifier)
          .show('Account linked. Your progress is saved.');
    }
    // A non-guest account just got linked or signed in: resume the invite the
    // guest was joining, if one is pending (consumed exactly once).
    if (signedInOrUpdated && user != null && !user.isAnonymous) {
      unawaited(_resumePendingInvite());
    }
  }

  Future<void> _resumePendingInvite() async {
    final code = await PendingInvite.consume();
    if (code != null) ref.read(inviteContinuationProvider.notifier).offer(code);
  }

  // ─── Helpers ────────────────────────────────────────────────────────

  AppUser? get currentUser => _client.currentUser;

  bool get isAuthenticated => currentUser != null;

  /// True when there is a session and it is anonymous. A missing session is
  /// *not* anonymous (nothing to link).
  bool get isAnonymous => currentUser?.isAnonymous ?? false;

  /// Lets tests pose as another platform; null in production.
  @visibleForTesting
  static AuthPlatform? platformOverride;

  static AuthPlatform get platform {
    final override = platformOverride;
    if (override != null) return override;
    if (kIsWeb) return AuthPlatform.other;
    if (Platform.isIOS) return AuthPlatform.ios;
    if (Platform.isAndroid) return AuthPlatform.android;
    return AuthPlatform.other;
  }

  BackendConfig? get _config => ref.read(backendConfigProvider).valueOrNull;

  String? get _googleWebClientId => _nonEmpty(_config?.googleWebClientId);
  String? get _googleIosClientId => _nonEmpty(_config?.googleIosClientId);

  static String? _nonEmpty(String? v) {
    final t = v?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  bool get _googleNativeConfigured => AuthStrategy.googleClientIdsConfigured(
    platform: platform,
    webClientId: _googleWebClientId,
    iosClientId: _googleIosClientId,
  );

  void _setUser() => state = AsyncValue.data(currentUser);

  void _flowStarted() => _flowsRunning++;

  void _flowFinished() {
    _flowsRunning--;
    _flowEndedAt = DateTime.now();
  }

  // ─── Anonymous ──────────────────────────────────────────────────────

  Future<AuthOutcome> signInAnonymously() async {
    if (currentUser != null) return AuthSuccess(user: currentUser);
    state = const AsyncValue.loading();
    final result = await _client.signInAnonymously();
    _setUser();
    switch (result) {
      case Success(data: final user):
        return AuthSuccess(user: user);
      case Failure(:final error):
        AppLogger.warn('Anonymous sign-in failed', error: error);
        return AuthFailure(AuthStrategy.friendlyError(error), raw: error);
    }
  }

  // ─── OAuth ──────────────────────────────────────────────────────────

  Future<AuthOutcome> signInWithGoogle() => _oauth(OAuthKind.google);

  Future<AuthOutcome> signInWithApple() => _oauth(OAuthKind.apple);

  /// Signs in to an *existing* account (used after an "identity already
  /// exists" response; the guest's local data stays under the guest's id).
  ///
  /// The guest session is not signed out first: `AuthClient` sends the guest
  /// bearer (the server then discards the guest) and replaces the stored
  /// session only once the provider returns one, so cancelling or failing
  /// leaves the guest usable. [switchToExistingAccount] re-creates one if
  /// anything lost it.
  Future<AuthOutcome> signInToExistingWithOAuth(OAuthKind provider) async {
    final outcome = await switchToExistingAccount(
      ensurer: ref.read(sessionEnsurerProvider),
      providerFlow: () => _oauth(provider, existingAccount: true),
    );
    _setUser();
    return outcome;
  }

  /// Signs in anonymously if there is no session; see [SessionEnsurer].
  /// Never throws; returns whether a session exists.
  Future<bool> ensureSession() async {
    final has = await ref.read(sessionEnsurerProvider).ensureSession();
    _setUser();
    return has;
  }

  Future<AuthOutcome> _oauth(
    OAuthKind provider, {
    bool existingAccount = false,
  }) async {
    final method = AuthStrategy.forOAuth(
      // Switching to an existing account must not link the guest identity.
      isAnonymous: isAnonymous && !existingAccount,
      platform: platform,
      provider: provider,
      hasClientIds: provider == OAuthKind.google
          ? _googleNativeConfigured
          : true,
    );
    final name = provider.name;

    state = const AsyncValue.loading();
    _flowStarted();
    try {
      final Result<AppUser, AppError> result;
      switch (method) {
        case OAuthMethod.linkWeb:
          result = await _launchWeb(name, link: true);
        case OAuthMethod.webOAuth:
          result = await _launchWeb(name, link: false);
        case OAuthMethod.linkNativeIdToken:
        case OAuthMethod.nativeIdToken:
          final native = ref.read(nativeSignInProvider);
          final token = switch (provider) {
            OAuthKind.google => await native.google(
              platform: platform,
              webClientId: _googleWebClientId,
              iosClientId: _googleIosClientId,
            ),
            OAuthKind.apple => await native.apple(),
          };
          if (token == null) {
            _setUser();
            return AuthFailure(switch (provider) {
              OAuthKind.google => 'Google did not return an ID token.',
              OAuthKind.apple => 'Apple did not return an identity token.',
            });
          }
          result = method.links
              ? await _client.linkWithIdToken(
                  provider: name,
                  idToken: token.idToken,
                  nonce: token.nonce,
                )
              : await _client.signInWithIdToken(
                  provider: name,
                  idToken: token.idToken,
                  nonce: token.nonce,
                );
      }
      _setUser();
      return _oauthOutcome(result, provider, method);
    } on SignInWithAppleAuthorizationException catch (e) {
      _setUser();
      if (e.code == AuthorizationErrorCode.canceled) {
        return const AuthCancelled();
      }
      AppLogger.warn('Apple sign-in failed', error: e);
      return AuthFailure(AuthStrategy.friendlyMessage(e.message), raw: e);
    } on GoogleSignInException catch (e) {
      _setUser();
      if (e.code == GoogleSignInExceptionCode.canceled) {
        return const AuthCancelled();
      }
      AppLogger.warn('Google sign-in failed', error: e);
      return AuthFailure(
        AuthStrategy.friendlyMessage(e.description ?? e.code.name),
        raw: e,
      );
    } on PlatformException catch (e) {
      _setUser();
      if (e.code == 'CANCELED' || e.code == 'CANCELLED') {
        return const AuthCancelled();
      }
      AppLogger.warn(
        'OAuth failed',
        data: {
          'provider': name,
          'method': method.name,
          'code': e.code,
          'message': AuthStrategy.redactUrls(e.message ?? ''),
        },
      );
      return const AuthFailure('Could not complete sign-in. Please try again.');
    } catch (e, st) {
      // The error text can embed the authorize URL; keep host + path only.
      final text = AuthStrategy.redactUrls(e.toString());
      AppLogger.warn('OAuth failed', error: text, st: st);
      _setUser();
      return AuthFailure(AuthStrategy.friendlyMessage(text));
    } finally {
      _flowFinished();
    }
  }

  AuthOutcome _oauthOutcome(
    Result<AppUser, AppError> result,
    OAuthKind provider,
    OAuthMethod method,
  ) {
    switch (result) {
      case Success(data: final user):
        if (method.links) {
          unawaited(
            AnalyticsService.logEvent(AnalyticsEvents.accountCreate, {
              'method': provider.name,
              'converted_guest': 'true',
            }),
          );
          return AuthSuccess(user: user, accountLinked: true);
        }
        final isNew = _isNewAccount(user);
        unawaited(
          AnalyticsService.logEvent(
            isNew ? AnalyticsEvents.accountCreate : AnalyticsEvents.signIn,
            {'method': provider.name},
          ),
        );
        return AuthSuccess(user: user, isNewAccount: isNew);
      case Failure(error: ConflictError(:final message)):
        return AuthIdentityExists(provider: provider, message: message);
      case Failure(error: CancelledError()):
        return const AuthCancelled();
      case Failure(:final error):
        AppLogger.warn(
          'OAuth failed',
          data: {
            'provider': provider.name,
            'method': method.name,
            'error': AuthStrategy.redactUrls(error.toString()),
          },
        );
        return AuthFailure(AuthStrategy.friendlyError(error), raw: error);
    }
  }

  /// Created within the last minute: a brand-new account rather than a
  /// returning one.
  static bool _isNewAccount(AppUser? user) {
    final createdAt = user?.createdAt;
    return createdAt != null &&
        DateTime.now().toUtc().difference(createdAt.toUtc()).inSeconds < 60;
  }

  /// Runs the browser flow (platform authentication session; it dismisses
  /// itself). [_webFlowOpen] is true only while the sheet is up, not while
  /// the callback is exchanged.
  Future<Result<AppUser, AppError>> _launchWeb(
    String provider, {
    required bool link,
  }) async {
    _webFlowOpen = true;
    try {
      return await _client.webOAuth(
        provider,
        link: link,
        onBrowserClosed: () => _webFlowOpen = false,
      );
    } finally {
      _webFlowOpen = false;
    }
  }

  /// App came back to the foreground. If a web sign-in is still showing the
  /// busy state, clear it: there is no completion signal when the person
  /// closes the sheet with Done/Cancel (SFSafariViewController) or Back
  /// (Custom Tab), and a session that did arrive has already replaced the
  /// state through [handleAuthEvent]. The guest session is untouched.
  @visibleForTesting
  void handleAppResumed() {
    if (!_webFlowOpen || !state.isLoading) return;
    // Re-check after a grace period: a resume while the sheet is still up
    // (lock screen, Face ID) must not hide the spinner early.
    _resumeTimer?.cancel();
    _resumeTimer = Timer(resumeGrace, () {
      if (_webFlowOpen && state.isLoading) _setUser();
    });
  }

  // ─── Email / password ───────────────────────────────────────────────

  /// Creates an account. For a guest this converts the anonymous user in
  /// place (`upgradeEmail`, same user id) so all progress is preserved.
  Future<AuthOutcome> signUpWithEmail(String email, String password) async {
    final method = AuthStrategy.forEmail(
      isAnonymous: isAnonymous,
      isSignUp: true,
    );
    if (method == EmailMethod.signInWithPassword) {
      return signInWithEmail(email, password);
    }
    state = const AsyncValue.loading();
    _flowStarted();
    try {
      final before = currentUser?.id;
      final result = method == EmailMethod.upgradeGuest
          ? await _client.upgradeEmail(email, password)
          : await _client.signUpEmail(email, password);
      _setUser();
      switch (result) {
        case Success(data: final user):
          final converted = method == EmailMethod.upgradeGuest;
          unawaited(
            AnalyticsService.logEvent(AnalyticsEvents.accountCreate, {
              'method': 'email',
              if (converted) 'converted_guest': 'true',
            }),
          );
          // A sign-up that returned no session (verification required)
          // leaves the previous session in place.
          if (!converted && currentUser?.id != user.id) {
            return AuthEmailConfirmationRequired(
              email: email,
              fromSignUp: true,
            );
          }
          return AuthSuccess(user: user, isNewAccount: true);
        case Failure(error: ConflictError(:final message)):
          return AuthIdentityExists(email: email, message: message);
        case Failure(:final error):
          AppLogger.warn(
            'Email sign-up failed',
            error: error,
            data: {'method': method.name, 'had_session': '${before != null}'},
          );
          return AuthFailure(AuthStrategy.friendlyError(error), raw: error);
      }
    } finally {
      _flowFinished();
    }
  }

  /// Signs in to an existing account. If a guest session is active it is
  /// replaced (guest data is abandoned — the UI warns about this).
  Future<AuthOutcome> signInWithEmail(String email, String password) async {
    state = const AsyncValue.loading();
    _flowStarted();
    try {
      final result = await _client.signInEmail(email, password);
      _setUser();
      switch (result) {
        case Success(data: final user):
          unawaited(
            AnalyticsService.logEvent(AnalyticsEvents.signIn, {
              'method': 'email',
            }),
          );
          return AuthSuccess(user: user);
        case Failure(:final error):
          AppLogger.warn('Email sign-in failed', error: error);
          return AuthFailure(AuthStrategy.friendlyError(error), raw: error);
      }
    } finally {
      _flowFinished();
    }
  }

  /// Sends the verification email again.
  Future<void> resendConfirmation(
    String email, {
    bool fromSignUp = false,
  }) async {
    final result = await _client.sendVerificationEmail(email: email);
    if (result case Failure(:final error)) {
      AppLogger.debug('Resend confirmation failed', error: error);
    }
  }

  // ─── Password recovery ──────────────────────────────────────────────

  /// Emails a password-reset link. An address with no account counts as
  /// success so the caller can show one neutral confirmation either way.
  Future<Result<void, AppError>> sendPasswordReset(String email) async {
    final result = await _client.requestPasswordReset(email);
    switch (result) {
      case Success():
        return const Result.success(null);
      case Failure(:final error):
        AppLogger.warn('Password reset request failed', error: error);
        return switch (AuthStrategy.classifyPasswordReset(error)) {
          PasswordResetFailure.unknownEmail => const Result.success(null),
          PasswordResetFailure.rateLimited => const Result.failure(
            AppError.rateLimit('Too many requests'),
          ),
          PasswordResetFailure.network => const Result.failure(
            AppError.network('No connection'),
          ),
          PasswordResetFailure.other => Result.failure(
            AppError.auth(AuthStrategy.friendlyError(error)),
          ),
        };
    }
  }

  /// Sets a new password with the token from the reset link that opened the
  /// app (see [PasswordRecoveryPending.token]).
  Future<Result<void, AppError>> updatePassword(String newPassword) {
    final token = ref.read(passwordRecoveryPendingProvider.notifier).token;
    if (token == null || token.isEmpty) {
      return Future.value(
        const Result.failure(
          AppError.auth(AuthStrategy.recoverySessionExpiredMessage),
        ),
      );
    }
    return completePasswordReset(token, newPassword);
  }

  /// Sets a new password for the account behind reset [token].
  Future<Result<void, AppError>> completePasswordReset(
    String token,
    String newPassword,
  ) async {
    final result = await _client.resetPassword(token, newPassword);
    switch (result) {
      case Success():
        return const Result.success(null);
      case Failure(:final error):
        AppLogger.warn('Password update failed', error: error);
        if (AuthStrategy.isRecoverySessionExpired(error)) {
          return const Result.failure(
            AppError.auth(AuthStrategy.recoverySessionExpiredMessage),
          );
        }
        if (error is NetworkError) return Result.failure(error);
        return Result.failure(AppError.auth(AuthStrategy.friendlyError(error)));
    }
  }

  // ─── Sign out ───────────────────────────────────────────────────────

  Future<void> signOut() async {
    // Always clears the local session; the server call is best effort.
    await _client.signOut();
    unawaited(AnalyticsService.logEvent(AnalyticsEvents.signOut));
    unawaited(AnalyticsService.setUserId(null));
    state = const AsyncValue.data(null);
    // Start a fresh guest session so the app keeps working offline-first.
    await ensureSession();
  }
}

/// `AuthClient.events` with the user after each event.
@riverpod
Stream<AuthStateChange> authStateChanges(Ref ref) {
  final client = ref.watch(authClientProvider);
  return client.events.map((e) => AuthStateChange(e, client.currentUser));
}

/// Whether the current session is a guest (or missing).
@riverpod
bool isGuest(Ref ref) {
  final user = ref.watch(authNotifierProvider).valueOrNull;
  return user?.isAnonymous ?? true;
}
