import '../../../core/backend/app_user.dart';

import 'auth_strategy.dart';

/// Result of an auth action, returned instead of thrown so screens can
/// switch on it without try/catch and the global auth state never becomes
/// an error just because a user typo'd a password.
sealed class AuthOutcome {
  const AuthOutcome();
}

/// The session was established / upgraded synchronously.
class AuthSuccess extends AuthOutcome {
  const AuthSuccess({
    required this.user,
    this.isNewAccount = false,
    this.accountLinked = false,
  });

  final AppUser? user;

  /// True when a guest was converted or a brand-new account was created.
  final bool isNewAccount;

  /// True when a guest was upgraded in place by linking a provider identity
  /// (progress kept); the UI says so instead of "Signed in.".
  final bool accountLinked;
}

/// The account was created but has no session yet: the user must confirm
/// the email first (the server returned no session token).
class AuthEmailConfirmationRequired extends AuthOutcome {
  const AuthEmailConfirmationRequired({
    required this.email,
    this.fromSignUp = false,
  });

  final String email;

  /// True when produced by a fresh sign-up; false for a guest upgrade.
  final bool fromSignUp;
}

/// The email / OAuth identity already belongs to another account. The UI
/// should offer to sign in to that account (abandoning guest data).
class AuthIdentityExists extends AuthOutcome {
  const AuthIdentityExists({this.email, this.provider, this.message});

  final String? email;
  final OAuthKind? provider;
  final String? message;
}

/// The user dismissed the native sign-in sheet.
class AuthCancelled extends AuthOutcome {
  const AuthCancelled();
}

class AuthFailure extends AuthOutcome {
  const AuthFailure(this.message, {this.raw});

  /// User-facing message.
  final String message;

  /// Original error, for logging.
  final Object? raw;
}
