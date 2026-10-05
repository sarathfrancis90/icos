/// Pure decision logic for choosing the right Supabase auth call.
///
/// Kept free of Flutter / Supabase imports so it is trivially unit-testable.
library;

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

/// Which Supabase call to make for an OAuth button press.
enum OAuthMethod {
  /// Anonymous user → `auth.linkIdentity(provider)` (web/PKCE flow). This is
  /// the only way to keep the guest's data: `signInWithIdToken` would create
  /// a brand-new user.
  linkIdentityWeb,

  /// No session or non-anonymous session, and a native SDK can produce an
  /// ID token → `auth.signInWithIdToken(...)`.
  nativeIdToken,

  /// No session or non-anonymous session, native not available →
  /// `auth.signInWithOAuth(provider)` (web/PKCE flow).
  webOAuth,
}

/// Which Supabase call to make for an email form submission.
enum EmailMethod {
  /// Anonymous user + "create account" → `auth.updateUser(email, password)`
  /// which converts the guest into a permanent user.
  updateUser,

  /// Fresh sign-up with no (or a non-anonymous) session → `auth.signUp`.
  signUp,

  /// Existing account → `auth.signInWithPassword`.
  signInWithPassword,
}

/// Redirect used for all web OAuth / linkIdentity flows.
const String kAuthRedirectUri = 'io.supabase.icos://login-callback';

abstract final class AuthStrategy {
  /// Decides how to handle an OAuth button press.
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
    if (isAnonymous) return OAuthMethod.linkIdentityWeb;
    if (nativeAvailable(
      platform: platform,
      provider: provider,
      hasClientIds: hasClientIds,
    )) {
      return OAuthMethod.nativeIdToken;
    }
    return OAuthMethod.webOAuth;
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
    return isAnonymous ? EmailMethod.updateUser : EmailMethod.signUp;
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

  /// Whether to render the Sign in with Apple button. Apple requires the
  /// button on iOS whenever third-party login is offered; on Android the
  /// web flow works but is hidden unless [allowWebOnAndroid].
  static bool showAppleButton(
    AuthPlatform platform, {
    bool allowWebOnAndroid = false,
  }) {
    return switch (platform) {
      AuthPlatform.ios => true,
      AuthPlatform.android => allowWebOnAndroid,
      AuthPlatform.other => false,
    };
  }

  /// Recognises Supabase's "this identity/email already belongs to another
  /// user" responses so the UI can offer to sign in to the existing account.
  static bool isIdentityAlreadyExists({String? code, String? message}) {
    final c = (code ?? '').toLowerCase();
    if (c == 'identity_already_exists' ||
        c == 'email_exists' ||
        c == 'user_already_exists') {
      return true;
    }
    final m = (message ?? '').toLowerCase();
    return m.contains('identity is already linked') ||
        m.contains('already registered') ||
        m.contains('already been registered') ||
        m.contains('email address is already') ||
        m.contains('already exists');
  }

  /// Recognises the "confirm your email" outcome of a guest → email
  /// conversion (Supabase with email confirmations enabled returns the user
  /// with `new_email` set and no confirmed email).
  static bool needsEmailConfirmation({
    required String? email,
    required String? newEmail,
    required String? emailConfirmedAt,
  }) {
    if (newEmail != null && newEmail.isNotEmpty) return true;
    if (email == null || email.isEmpty) return false;
    return emailConfirmedAt == null || emailConfirmedAt.isEmpty;
  }

  /// Classifies an error from `resetPasswordForEmail`.
  static PasswordResetFailure classifyPasswordReset({
    String? code,
    String? statusCode,
    String? message,
  }) {
    final c = (code ?? '').toLowerCase();
    final m = (message ?? '').toLowerCase();
    // The per-email send limit ("For security purposes, you can only request
    // this after N seconds") only trips for an address that really got a mail,
    // so reporting it differently would reveal that the account exists. It
    // gets the same neutral confirmation. Only request/IP-wide limits are
    // shown as "try again later".
    if (c == 'user_not_found' ||
        c == 'over_email_send_rate_limit' ||
        m.contains('user not found') ||
        m.contains('unable to validate email') ||
        m.contains('security purposes')) {
      return PasswordResetFailure.unknownEmail;
    }
    if (c.contains('rate_limit') ||
        statusCode == '429' ||
        m.contains('rate limit') ||
        m.contains('too many')) {
      return PasswordResetFailure.rateLimited;
    }
    if (m.contains('network') ||
        m.contains('socket') ||
        m.contains('failed host lookup') ||
        m.contains('clientexception')) {
      return PasswordResetFailure.network;
    }
    return PasswordResetFailure.other;
  }

  /// Message carried by the failure when the recovery session behind the
  /// "set a new password" screen is no longer valid.
  static const String recoverySessionExpiredMessage = 'recovery_session_expired';

  /// True when `updateUser` failed because the session from the recovery link
  /// has expired or is gone (so only a new link can help).
  static bool isRecoverySessionExpired({
    String? code,
    String? statusCode,
    String? message,
  }) {
    final c = (code ?? '').toLowerCase();
    if (c == 'session_not_found' ||
        c == 'session_expired' ||
        c == 'bad_jwt' ||
        c == 'refresh_token_not_found' ||
        c == 'refresh_token_already_used') {
      return true;
    }
    final m = (message ?? '').toLowerCase();
    return statusCode == '401' ||
        m.contains('session missing') ||
        m.contains('session not found') ||
        m.contains('jwt expired') ||
        m.contains('token has expired') ||
        m.contains('invalid jwt');
  }

  /// Maps raw provider/Supabase errors to friendly copy.
  static String friendlyMessage(String raw) {
    final e = raw.toLowerCase();
    if (e.contains('invalid login credentials') ||
        e.contains('invalid_credentials')) {
      return 'Invalid email or password. Please try again.';
    }
    if (isIdentityAlreadyExists(message: e)) {
      return 'An account with this email already exists.';
    }
    if (e.contains('email not confirmed')) {
      return 'Please check your email to confirm your account.';
    }
    if (e.contains('rate limit') || e.contains('too many')) {
      return 'Too many attempts. Please wait a moment.';
    }
    if (e.contains('different from the old password') ||
        e.contains('same_password')) {
      return 'Choose a password you have not used before.';
    }
    if (e.contains('password should be') || e.contains('weak password')) {
      return 'Please choose a stronger password (at least 6 characters).';
    }
    if (e.contains('network') ||
        e.contains('socket') ||
        e.contains('failed host lookup')) {
      return 'No internet connection. Please try again.';
    }
    return 'Something went wrong. Please try again.';
  }
}
