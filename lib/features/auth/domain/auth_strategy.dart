/// Pure decision logic for choosing the right `AuthClient` call.
///
/// Kept free of Flutter / SDK imports so it is trivially unit-testable.
library;

import '../../../core/utils/app_error.dart';

enum AuthPlatform { ios, android, other }

enum OAuthKind { google, apple }

/// How a failed "send password reset email" request should be reported.
enum PasswordResetFailure {
  /// The address has no account. Reported exactly like success so the form
  /// cannot be used to find out who has an account.
  unknownEmail,
  rateLimited,
  network,
  other,
}

/// Which `AuthClient` call to make for an OAuth button press.
///
/// | platform | Google                | Apple                 |
/// |----------|-----------------------|-----------------------|
/// | iOS      | native ID token       | native ID token       |
/// | Android  | native ID token       | web (`webOAuth`)      |
/// | other    | web                   | web                   |
///
/// Google falls back to the web flow when its client ids are missing. A
/// guest links (same user id, progress kept); anyone else signs in.
enum OAuthMethod {
  /// Guest + native ID token → `AuthClient.linkWithIdToken`.
  linkNativeIdToken,

  /// Guest, no native SDK → `AuthClient.webOAuth(provider, link: true)`.
  linkWeb,

  /// Not a guest (or switching to an existing account) + native ID token →
  /// `AuthClient.signInWithIdToken` (the guest bearer is sent, so the server
  /// discards the guest).
  nativeIdToken,

  /// Not a guest, no native SDK → `AuthClient.webOAuth(provider)`.
  webOAuth;

  /// True for the guest-upgrade methods (the user id is kept).
  bool get links => this == linkNativeIdToken || this == linkWeb;
}

/// Which `AuthClient` call to make for an email form submission.
enum EmailMethod {
  /// Guest + "create account" → `AuthClient.upgradeEmail` (same user id).
  upgradeGuest,

  /// Fresh sign-up with no (or a non-anonymous) session →
  /// `AuthClient.signUpEmail`.
  signUp,

  /// Existing account → `AuthClient.signInEmail`.
  signInWithPassword,
}

/// Callback for web OAuth (Google/Apple): the flutter_web_auth_2 scheme
/// (`kOAuthCallbackUrl` in `backend_config.dart`). On Android the package's
/// `CallbackActivity` owns it.
const String kOAuthRedirectUri = 'io.icos://oauth-callback';

abstract final class AuthStrategy {
  /// Replaces every URL in [text] with just its host and path, so a log line
  /// never carries the authorize URL (state, PKCE challenge, redirect).
  static String redactUrls(String text) =>
      text.replaceAllMapped(RegExp(r'[a-zA-Z][a-zA-Z0-9+.-]*://[^\s<>]+'), (m) {
        final uri = Uri.tryParse(m[0]!);
        if (uri == null) return '<url>';
        return '${uri.host}${uri.path}';
      });

  /// Decides how to handle an OAuth button press (see [OAuthMethod]).
  ///
  /// [hasClientIds] — for Google: whether `GOOGLE_WEB_CLIENT_ID` (and on iOS
  /// `GOOGLE_IOS_CLIENT_ID`) are configured. For Apple it is ignored: native
  /// Sign in with Apple needs no client id but is only available on iOS.
  static OAuthMethod forOAuth({
    required bool isAnonymous,
    required AuthPlatform platform,
    required OAuthKind provider,
    required bool hasClientIds,
  }) {
    final native = nativeAvailable(
      platform: platform,
      provider: provider,
      hasClientIds: hasClientIds,
    );
    if (isAnonymous) {
      return native ? OAuthMethod.linkNativeIdToken : OAuthMethod.linkWeb;
    }
    return native ? OAuthMethod.nativeIdToken : OAuthMethod.webOAuth;
  }

  /// Whether a native (in-app) sign-in SDK can be used.
  static bool nativeAvailable({
    required AuthPlatform platform,
    required OAuthKind provider,
    required bool hasClientIds,
  }) {
    return switch (provider) {
      OAuthKind.apple => platform == AuthPlatform.ios,
      OAuthKind.google =>
        (platform == AuthPlatform.ios || platform == AuthPlatform.android) &&
            hasClientIds,
    };
  }

  /// Decides how to handle an email/password submission.
  static EmailMethod forEmail({
    required bool isAnonymous,
    required bool isSignUp,
  }) {
    if (!isSignUp) return EmailMethod.signInWithPassword;
    return isAnonymous ? EmailMethod.upgradeGuest : EmailMethod.signUp;
  }

  /// Whether Google client ids are sufficient for the native SDK on
  /// [platform]. Android only needs the web (server) client id; iOS needs
  /// both.
  static bool googleClientIdsConfigured({
    required AuthPlatform platform,
    required String? webClientId,
    required String? iosClientId,
  }) {
    final hasWeb = webClientId != null && webClientId.trim().isNotEmpty;
    final hasIos = iosClientId != null && iosClientId.trim().isNotEmpty;
    return switch (platform) {
      AuthPlatform.android => hasWeb,
      AuthPlatform.ios => hasWeb && hasIos,
      AuthPlatform.other => false,
    };
  }

  /// Whether to render the Sign in with Apple button: on iOS (required by
  /// Apple whenever third-party login is offered) and on Android, where it
  /// always runs the web flow ([nativeAvailable] is false there) so it can
  /// sit beside Google at equal prominence.
  static bool showAppleButton(AuthPlatform platform) {
    return switch (platform) {
      AuthPlatform.ios || AuthPlatform.android => true,
      AuthPlatform.other => false,
    };
  }

  /// Recognises "this identity/email already belongs to another user"
  /// codes and messages (Better Auth; `AuthClient` already maps them to
  /// [AppError.conflict], this covers free text such as friendly copy).
  static bool isIdentityAlreadyExists({String? code, String? message}) {
    final c = (code ?? '').toLowerCase();
    if (c == 'email_exists' ||
        c.startsWith('user_already_exists') ||
        c.contains('already_linked')) {
      return true;
    }
    final m = (message ?? '').toLowerCase();
    return m.contains('already linked') ||
        m.contains('already registered') ||
        m.contains('already been registered') ||
        m.contains('email address is already') ||
        m.contains('already exists');
  }

  /// Classifies a failed `request-password-reset`.
  static PasswordResetFailure classifyPasswordReset(AppError error) {
    switch (error) {
      case NotFoundError():
        return PasswordResetFailure.unknownEmail;
      case RateLimitError():
        return PasswordResetFailure.rateLimited;
      case NetworkError():
        return PasswordResetFailure.network;
      case ValidationError(:final message) || AuthError(:final message):
        final m = message.toLowerCase();
        // Format validation already passed on the client, so a server-side
        // "user not found" / "invalid email" answer is neutral: reporting it
        // differently would reveal whether the account exists.
        if (m.contains('not found') ||
            (m.contains('email') && m.contains('invalid'))) {
          return PasswordResetFailure.unknownEmail;
        }
        return PasswordResetFailure.other;
      default:
        return PasswordResetFailure.other;
    }
  }

  /// Message carried by the failure when the reset token behind the "set a
  /// new password" screen is missing, used or expired.
  static const String recoverySessionExpiredMessage =
      'recovery_session_expired';

  /// True when `reset-password` failed because the token from the reset
  /// link is no longer valid (so only a new link can help).
  static bool isRecoverySessionExpired(AppError error) {
    final String message;
    switch (error) {
      case AuthError(message: final m) ||
          ValidationError(message: final m) ||
          NotFoundError(message: final m):
        message = m.toLowerCase();
      default:
        return false;
    }
    if (error is AuthError) return true;
    return message.contains('invalid token') ||
        message.contains('invalid_token') ||
        message.contains('expired');
  }

  /// User-facing copy for an [AppError] from `AuthClient`.
  static String friendlyError(AppError error) => switch (error) {
    NetworkError() => 'No internet connection. Please try again.',
    RateLimitError() => 'Too many attempts. Please wait a moment.',
    ConflictError() => 'An account with this email already exists.',
    CancelledError() => error.userMessage,
    AuthError(:final message) ||
    ValidationError(:final message) ||
    NotFoundError(:final message) ||
    DatabaseError(:final message) ||
    UnknownError(:final message) => friendlyMessage(message),
  };

  /// Maps raw provider/server errors to friendly copy.
  static String friendlyMessage(String raw) {
    final e = raw.toLowerCase();
    if (e.contains('invalid login credentials') ||
        e.contains('invalid_credentials') ||
        e.contains('invalid email or password') ||
        e.contains('invalid_email_or_password')) {
      return 'Invalid email or password. Please try again.';
    }
    if (isIdentityAlreadyExists(message: e)) {
      return 'An account with this email already exists.';
    }
    if (e.contains('email not confirmed') || e.contains('email not verified')) {
      return 'Please check your email to confirm your account.';
    }
    if (e.contains('rate limit') || e.contains('too many')) {
      return 'Too many attempts. Please wait a moment.';
    }
    if (e.contains('different from the old password') ||
        e.contains('same_password')) {
      return 'Choose a password you have not used before.';
    }
    if (e.contains('password should be') ||
        e.contains('weak password') ||
        e.contains('password too short') ||
        e.contains('password_too_short')) {
      return 'Please choose a stronger password (at least 6 characters).';
    }
    if (e.contains('network') ||
        e.contains('socket') ||
        e.contains('failed host lookup') ||
        e.contains('no internet')) {
      return 'No internet connection. Please try again.';
    }
    return 'Something went wrong. Please try again.';
  }
}
