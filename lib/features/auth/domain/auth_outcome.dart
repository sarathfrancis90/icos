import 'package:supabase_flutter/supabase_flutter.dart' show User;

import 'auth_strategy.dart';

/// Result of an auth action, returned instead of thrown so screens can
/// switch on it without try/catch and the global auth state never becomes
/// an error just because a user typo'd a password.
sealed class AuthOutcome {
  const AuthOutcome();
}

/// The session was established / upgraded synchronously.
class AuthSuccess extends AuthOutcome {
  const AuthSuccess({required this.user, this.isNewAccount = false});

  final User? user;

  /// True when a guest was converted or a brand-new account was created.
  final bool isNewAccount;
}

/// A browser / external app was opened for a PKCE flow. The session will
/// arrive later via the deep link; watch `authNotifierProvider` /
/// `authFlowMessageProvider` for the result.
class AuthRedirected extends AuthOutcome {
  const AuthRedirected({required this.provider, required this.linking});

  final OAuthKind provider;

  /// True when the flow is `linkIdentity` (guest upgrade).
  final bool linking;
}

/// Supabase requires the user to confirm the new email before the account
/// becomes usable with that email.
class AuthEmailConfirmationRequired extends AuthOutcome {
  const AuthEmailConfirmationRequired({
    required this.email,
    this.fromSignUp = false,
  });

  final String email;

  /// True when produced by a fresh `signUp` (resend uses `OtpType.signup`);
  /// false for a guest upgrade via `updateUser` (`OtpType.emailChange`).
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
