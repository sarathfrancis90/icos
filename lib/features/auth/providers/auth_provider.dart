import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/analytics_service.dart';
import '../../../core/services/app_logger.dart';
import '../../../core/services/session_service.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/utils/app_error.dart';
import '../../../core/utils/result.dart';
import '../domain/auth_outcome.dart';
import '../domain/auth_strategy.dart';

export '../domain/auth_outcome.dart';
export '../domain/auth_strategy.dart' show OAuthKind;

part 'auth_provider.g.dart';

/// One-shot user-facing messages produced by asynchronous auth events
/// (deep-link callbacks, identity-link failures). Screens `ref.listen` to
/// this, show a SnackBar and call [AuthFlowMessage.clear].
@riverpod
class AuthFlowMessage extends _$AuthFlowMessage {
  @override
  String? build() => null;

  void show(String message) => state = message;

  void clear() => state = null;
}

/// One-shot signal that an asynchronous (deep-link) sign-in came back with
/// "this identity already belongs to another account".
///
/// Kept separate from [AuthFlowMessage] because this one is not a message. It
/// needs an action: offer to sign in to that account instead. The web redirect
/// flow reports it through the auth error stream, long after the call that
/// started it has returned, so there is no outcome to hand back.
@riverpod
class AuthIdentityConflict extends _$AuthIdentityConflict {
  @override
  OAuthKind? build() => null;

  void show(OAuthKind? provider) => state = provider;

  void clear() => state = null;
}

/// Set by `main()` when a password-recovery link was opened before the app's
/// providers existed, so the recovery screen is still shown.
abstract final class PasswordRecoveryLatch {
  static bool arrivedBeforeStart = false;
}

/// True when the recovery link replaced a guest profile that has progress on
/// this device, so the "set a new password" screen can warn that it will not
/// carry over.
@Riverpod(keepAlive: true)
class RecoveryReplacesGuest extends _$RecoveryReplacesGuest {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

/// True from the moment a password-recovery link signs the player in until
/// they set a new password (or dismiss the screen). The router sends the
/// player to the "set a new password" screen while this is true.
@Riverpod(keepAlive: true)
class PasswordRecoveryPending extends _$PasswordRecoveryPending {
  /// The guest session active before the event, if any.
  String? _guestId;

  @override
  bool build() {
    final current = ref.read(authNotifierProvider).valueOrNull;
    if (current != null && current.isAnonymous) _guestId = current.id;

    ref.listen<AsyncValue<AuthState>>(authStateChangesProvider, (_, next) {
      final data = next.valueOrNull;
      if (data == null) return;
      final user = data.session?.user;
      if (data.event == AuthChangeEvent.passwordRecovery) {
        final guest = _guestId;
        ref.read(recoveryReplacesGuestProvider.notifier).set(
              guest != null &&
                  guest != user?.id &&
                  StorageService.hasLocalProgress(guest),
            );
        state = true;
      } else if (user != null && user.isAnonymous) {
        _guestId = user.id;
      } else if (data.event == AuthChangeEvent.signedOut) {
        _guestId = null;
      }
    });
    final early = PasswordRecoveryLatch.arrivedBeforeStart;
    PasswordRecoveryLatch.arrivedBeforeStart = false;
    return early;
  }

  /// Recovery finished (password set) or was dismissed.
  void clear() {
    PasswordRecoveryLatch.arrivedBeforeStart = false;
    ref.read(recoveryReplacesGuestProvider.notifier).set(false);
    state = false;
  }
}

@riverpod
class AuthNotifier extends _$AuthNotifier {
  StreamSubscription<AuthState>? _subscription;
  bool _googleInitialized = false;

  /// Provider behind the redirect currently in flight. The auth error stream
  /// does not say which provider failed, so remember it on the way out.
  OAuthKind? _pendingRedirectProvider;

  @override
  AsyncValue<User?> build() {
    _subscription?.cancel();
    _subscription = SupabaseService.auth.onAuthStateChange.listen(
      _onAuthEvent,
      onError: _onAuthError,
    );
    ref.onDispose(() => _subscription?.cancel());
    return AsyncValue.data(SupabaseService.auth.currentUser);
  }

  void _onAuthEvent(AuthState data) {
    final user = data.session?.user ?? SupabaseService.auth.currentUser;
    state = AsyncValue.data(user);
    if (data.event == AuthChangeEvent.userUpdated ||
        data.event == AuthChangeEvent.signedIn) {
      unawaited(AnalyticsService.setUserId(user?.id));
    }
    if (data.event == AuthChangeEvent.userUpdated &&
        user != null &&
        !user.isAnonymous) {
      // Deep-link linkIdentity completed for a former guest.
      _pendingRedirectProvider = null;
      ref.read(authFlowMessageProvider.notifier).show(
            'Account linked. Your progress is saved.',
          );
    }
  }

  void _onAuthError(Object error, StackTrace st) {
    AppLogger.warn('Auth stream error', error: error, st: st);
    final provider = _pendingRedirectProvider;
    _pendingRedirectProvider = null;

    if (error is AuthException &&
        AuthStrategy.isIdentityAlreadyExists(
            code: error.code, message: error.message)) {
      // Offer the way out rather than describing the problem.
      ref.read(authIdentityConflictProvider.notifier).show(provider);
      state = AsyncValue.data(SupabaseService.auth.currentUser);
      return;
    }

    final message = error is AuthException
        ? AuthStrategy.friendlyMessage(error.message)
        : AuthStrategy.friendlyMessage(error.toString());
    ref.read(authFlowMessageProvider.notifier).show(message);
    state = AsyncValue.data(SupabaseService.auth.currentUser);
  }

  // ─── Helpers ────────────────────────────────────────────────────────

  User? get currentUser => SupabaseService.auth.currentUser;

  bool get isAuthenticated => currentUser != null;

  /// True when there is a session and it is anonymous. A missing session is
  /// *not* anonymous (nothing to link).
  bool get isAnonymous => currentUser?.isAnonymous ?? false;

  static AuthPlatform get platform {
    if (kIsWeb) return AuthPlatform.other;
    if (Platform.isIOS) return AuthPlatform.ios;
    if (Platform.isAndroid) return AuthPlatform.android;
    return AuthPlatform.other;
  }

  static String? _env(String key) {
    try {
      if (!dotenv.isInitialized) return null;
      final v = dotenv.env[key]?.trim();
      return (v == null || v.isEmpty) ? null : v;
    } catch (_) {
      return null;
    }
  }

  static String? get googleWebClientId => _env('GOOGLE_WEB_CLIENT_ID');
  static String? get googleIosClientId => _env('GOOGLE_IOS_CLIENT_ID');

  static bool get googleNativeConfigured =>
      AuthStrategy.googleClientIdsConfigured(
        platform: platform,
        webClientId: googleWebClientId,
        iosClientId: googleIosClientId,
      );

  void _setUser() => state = AsyncValue.data(currentUser);

  // ─── Anonymous ──────────────────────────────────────────────────────

  Future<AuthOutcome> signInAnonymously() async {
    if (currentUser != null) return AuthSuccess(user: currentUser);
    state = const AsyncValue.loading();
    try {
      final res = await SupabaseService.auth.signInAnonymously();
      _setUser();
      return AuthSuccess(user: res.user);
    } on AuthException catch (e, st) {
      AppLogger.warn('Anonymous sign-in failed', error: e, st: st);
      _setUser();
      return AuthFailure(AuthStrategy.friendlyMessage(e.message), raw: e);
    } catch (e, st) {
      AppLogger.warn('Anonymous sign-in failed', error: e, st: st);
      _setUser();
      return AuthFailure(AuthStrategy.friendlyMessage(e.toString()), raw: e);
    }
  }

  // ─── OAuth ──────────────────────────────────────────────────────────

  Future<AuthOutcome> signInWithGoogle() =>
      _oauth(OAuthKind.google, hasClientIds: googleNativeConfigured);

  Future<AuthOutcome> signInWithApple() =>
      _oauth(OAuthKind.apple, hasClientIds: true);

  /// Signs in to an *existing* account (used after an "identity already
  /// exists" response; the guest's local data stays under the guest's id).
  ///
  /// The guest session is not signed out first: the SDK replaces it once the
  /// provider returns a session, so cancelling or failing leaves the guest
  /// usable. [switchToExistingAccount] re-creates one if anything lost it.
  Future<AuthOutcome> signInToExistingWithOAuth(OAuthKind provider) async {
    final outcome = await switchToExistingAccount(
      ensurer: ref.read(sessionEnsurerProvider),
      providerFlow: () => _oauth(
        provider,
        hasClientIds:
            provider == OAuthKind.google ? googleNativeConfigured : true,
        existingAccount: true,
      ),
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
    required bool hasClientIds,
    bool existingAccount = false,
  }) async {
    final method = AuthStrategy.forOAuth(
      // Switching to an existing account must not link the guest identity.
      isAnonymous: isAnonymous && !existingAccount,
      platform: platform,
      provider: provider,
      hasClientIds: hasClientIds,
    );
    final supabaseProvider = switch (provider) {
      OAuthKind.google => OAuthProvider.google,
      OAuthKind.apple => OAuthProvider.apple,
    };

    state = const AsyncValue.loading();
    try {
      switch (method) {
        case OAuthMethod.linkIdentityWeb:
          _pendingRedirectProvider = provider;
          await SupabaseService.auth.linkIdentity(
            supabaseProvider,
            redirectTo: kAuthRedirectUri,
            authScreenLaunchMode: LaunchMode.externalApplication,
          );
          _setUser();
          return AuthRedirected(provider: provider, linking: true);

        case OAuthMethod.webOAuth:
          _pendingRedirectProvider = provider;
          await SupabaseService.auth.signInWithOAuth(
            supabaseProvider,
            redirectTo: kAuthRedirectUri,
            authScreenLaunchMode: LaunchMode.externalApplication,
          );
          _setUser();
          return AuthRedirected(provider: provider, linking: false);

        case OAuthMethod.nativeIdToken:
          final outcome = switch (provider) {
            OAuthKind.google => await _nativeGoogle(),
            OAuthKind.apple => await _nativeApple(),
          };
          _setUser();
          return outcome;
      }
    } on AuthException catch (e, st) {
      AppLogger.warn('OAuth failed', error: e, st: st, data: {
        'provider': provider.name,
        'method': method.name,
        'code': e.code,
      });
      _setUser();
      if (AuthStrategy.isIdentityAlreadyExists(
          code: e.code, message: e.message)) {
        return AuthIdentityExists(provider: provider, message: e.message);
      }
      return AuthFailure(AuthStrategy.friendlyMessage(e.message), raw: e);
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
    } catch (e, st) {
      AppLogger.warn('OAuth failed', error: e, st: st);
      _setUser();
      return AuthFailure(AuthStrategy.friendlyMessage(e.toString()), raw: e);
    }
  }

  Future<AuthOutcome> _nativeGoogle() async {
    final gsi = GoogleSignIn.instance;
    if (!_googleInitialized) {
      await gsi.initialize(
        clientId: platform == AuthPlatform.ios ? googleIosClientId : null,
        serverClientId: googleWebClientId,
      );
      _googleInitialized = true;
    }
    final account = await gsi.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null || idToken.isEmpty) {
      return const AuthFailure('Google did not return an ID token.');
    }
    final res = await SupabaseService.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
    );
    return _afterNativeSignIn(res, 'google');
  }

  Future<AuthOutcome> _nativeApple() async {
    final rawNonce = _generateNonce();
    final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();
    final credential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: hashedNonce,
    );
    final idToken = credential.identityToken;
    if (idToken == null || idToken.isEmpty) {
      return const AuthFailure('Apple did not return an identity token.');
    }
    final res = await SupabaseService.auth.signInWithIdToken(
      provider: OAuthProvider.apple,
      idToken: idToken,
      nonce: rawNonce,
    );
    return _afterNativeSignIn(res, 'apple');
  }

  AuthOutcome _afterNativeSignIn(AuthResponse res, String method) {
    final user = res.user;
    final createdAt = DateTime.tryParse(user?.createdAt ?? '');
    final isNew = createdAt != null &&
        DateTime.now().toUtc().difference(createdAt.toUtc()).inSeconds < 60;
    unawaited(AnalyticsService.logEvent(
      isNew ? AnalyticsEvents.accountCreate : AnalyticsEvents.signIn,
      {'method': method},
    ));
    return AuthSuccess(user: user, isNewAccount: isNew);
  }

  static String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)])
        .join();
  }

  // ─── Email / password ───────────────────────────────────────────────

  /// Creates an account. For a guest this converts the anonymous user via
  /// `updateUser` so all progress is preserved.
  Future<AuthOutcome> signUpWithEmail(String email, String password) async {
    final method =
        AuthStrategy.forEmail(isAnonymous: isAnonymous, isSignUp: true);
    state = const AsyncValue.loading();
    try {
      switch (method) {
        case EmailMethod.updateUser:
          final res = await SupabaseService.auth.updateUser(
            UserAttributes(email: email, password: password),
            emailRedirectTo: kAuthRedirectUri,
          );
          _setUser();
          final user = res.user ?? currentUser;
          unawaited(AnalyticsService.logEvent(
            AnalyticsEvents.accountCreate,
            {'method': 'email', 'converted_guest': 'true'},
          ));
          if (AuthStrategy.needsEmailConfirmation(
            email: user?.email,
            newEmail: user?.newEmail,
            emailConfirmedAt: user?.emailConfirmedAt,
          )) {
            return AuthEmailConfirmationRequired(email: email);
          }
          return AuthSuccess(user: user, isNewAccount: true);

        case EmailMethod.signUp:
          final res = await SupabaseService.auth.signUp(
            email: email,
            password: password,
            emailRedirectTo: kAuthRedirectUri,
          );
          _setUser();
          unawaited(AnalyticsService.logEvent(
            AnalyticsEvents.accountCreate,
            {'method': 'email'},
          ));
          if (res.session == null) {
            return AuthEmailConfirmationRequired(email: email, fromSignUp: true);
          }
          return AuthSuccess(user: res.user, isNewAccount: true);

        case EmailMethod.signInWithPassword:
          return signInWithEmail(email, password);
      }
    } on AuthException catch (e, st) {
      AppLogger.warn('Email sign-up failed',
          error: e, st: st, data: {'method': method.name, 'code': e.code});
      _setUser();
      if (AuthStrategy.isIdentityAlreadyExists(
          code: e.code, message: e.message)) {
        return AuthIdentityExists(email: email, message: e.message);
      }
      return AuthFailure(AuthStrategy.friendlyMessage(e.message), raw: e);
    } catch (e, st) {
      AppLogger.warn('Email sign-up failed', error: e, st: st);
      _setUser();
      return AuthFailure(AuthStrategy.friendlyMessage(e.toString()), raw: e);
    }
  }

  /// Signs in to an existing account. If a guest session is active it is
  /// replaced (guest data is abandoned — the UI warns about this).
  Future<AuthOutcome> signInWithEmail(String email, String password) async {
    state = const AsyncValue.loading();
    try {
      final res = await SupabaseService.auth.signInWithPassword(
        email: email,
        password: password,
      );
      _setUser();
      unawaited(AnalyticsService.logEvent(
        AnalyticsEvents.signIn,
        {'method': 'email'},
      ));
      return AuthSuccess(user: res.user);
    } on AuthException catch (e, st) {
      AppLogger.warn('Email sign-in failed',
          error: e, st: st, data: {'code': e.code});
      _setUser();
      return AuthFailure(AuthStrategy.friendlyMessage(e.message), raw: e);
    } catch (e, st) {
      AppLogger.warn('Email sign-in failed', error: e, st: st);
      _setUser();
      return AuthFailure(AuthStrategy.friendlyMessage(e.toString()), raw: e);
    }
  }

  Future<void> resendConfirmation(String email, {bool fromSignUp = false}) async {
    try {
      await SupabaseService.auth.resend(
        type: fromSignUp ? OtpType.signup : OtpType.emailChange,
        email: email,
        emailRedirectTo: kAuthRedirectUri,
      );
    } catch (e) {
      AppLogger.debug('Resend confirmation failed', error: e);
    }
  }

  // ─── Password recovery ──────────────────────────────────────────────

  /// Emails a password-reset link. An address with no account counts as
  /// success so the caller can show one neutral confirmation either way.
  Future<Result<void, AppError>> sendPasswordReset(String email) async {
    try {
      await SupabaseService.auth.resetPasswordForEmail(
        email,
        redirectTo: kAuthRedirectUri,
      );
      return const Result.success(null);
    } on AuthException catch (e, st) {
      AppLogger.warn('Password reset request failed',
          error: e, st: st, data: {'code': e.code});
      return switch (AuthStrategy.classifyPasswordReset(
        code: e.code,
        statusCode: e.statusCode,
        message: e.message,
      )) {
        PasswordResetFailure.unknownEmail => const Result.success(null),
        PasswordResetFailure.rateLimited =>
          const Result.failure(AppError.rateLimit('Too many requests')),
        PasswordResetFailure.network =>
          const Result.failure(AppError.network('No connection')),
        PasswordResetFailure.other =>
          Result.failure(AppError.auth(AuthStrategy.friendlyMessage(e.message))),
      };
    } catch (e, st) {
      AppLogger.warn('Password reset request failed', error: e, st: st);
      return Result.failure(
        AppError.network(AuthStrategy.friendlyMessage(e.toString())),
      );
    }
  }

  /// Sets a new password for the signed-in (recovery) session.
  Future<Result<void, AppError>> updatePassword(String newPassword) async {
    try {
      await SupabaseService.auth.updateUser(
        UserAttributes(password: newPassword),
      );
      return const Result.success(null);
    } on AuthException catch (e, st) {
      AppLogger.warn('Password update failed',
          error: e, st: st, data: {'code': e.code});
      if (AuthStrategy.isRecoverySessionExpired(
        code: e.code,
        statusCode: e.statusCode,
        message: e.message,
      )) {
        return const Result.failure(
          AppError.auth(AuthStrategy.recoverySessionExpiredMessage),
        );
      }
      return Result.failure(
        AppError.auth(AuthStrategy.friendlyMessage(e.message)),
      );
    } catch (e, st) {
      AppLogger.warn('Password update failed', error: e, st: st);
      return Result.failure(
        AppError.network(AuthStrategy.friendlyMessage(e.toString())),
      );
    }
  }

  // ─── Sign out ───────────────────────────────────────────────────────

  Future<void> signOut() async {
    try {
      await SupabaseService.auth.signOut();
      unawaited(AnalyticsService.logEvent(AnalyticsEvents.signOut));
      unawaited(AnalyticsService.setUserId(null));
    } catch (e, st) {
      // gotrue clears the local session (and emits signedOut) before it calls
      // the server, so a network failure here only means the server-side
      // session was not revoked. Make sure the local one is gone regardless.
      AppLogger.warn('Sign out failed', error: e, st: st);
      try {
        await SupabaseService.auth.signOut(scope: SignOutScope.local);
      } catch (_) {}
    }
    state = const AsyncValue.data(null);
    // Start a fresh guest session so the app keeps working offline-first.
    await ensureSession();
  }
}

@riverpod
Stream<AuthState> authStateChanges(Ref ref) {
  return SupabaseService.auth.onAuthStateChange;
}

/// Whether the current session is a guest (or missing).
@riverpod
bool isGuest(Ref ref) {
  final user = ref.watch(authNotifierProvider).valueOrNull;
  return user?.isAnonymous ?? true;
}
