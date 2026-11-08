import 'dart:async';

import 'package:icos/core/backend/app_user.dart';
import 'package:icos/core/backend/auth_client.dart';
import 'package:icos/core/backend/auth_event.dart';
import 'package:icos/core/utils/app_error.dart';
import 'package:icos/core/utils/result.dart';

/// A guest (anonymous) [AppUser].
AppUser guestUser([String id = 'g']) =>
    AppUser(id: id, isAnonymous: true, createdAt: DateTime.utc(2026, 10, 5));

/// A registered [AppUser].
AppUser memberUser([
  String id = 'u',
  String? email = 'u@example.test',
  List<String> providers = const ['google'],
]) => AppUser(
  id: id,
  email: email,
  emailVerified: true,
  providers: providers,
  createdAt: DateTime.utc(2026, 10, 5),
);

/// In-memory [AuthClient] for tests: records calls, returns scripted
/// results and behaves like the real client on success (updates
/// [currentUser] and emits the matching [AuthEvent]).
class FakeAuthClient implements AuthClient {
  FakeAuthClient({AppUser? user}) : _user = user;

  AppUser? _user;
  final _events = StreamController<AuthEvent>.broadcast();

  /// One line per call, e.g. `linkWithIdToken:google:tok`.
  final calls = <String>[];

  /// Scripted results; null means "succeed with a sensible user".
  Result<AppUser, AppError>? signInAnonymouslyResult;
  Result<AppUser, AppError>? signUpEmailResult;
  Result<AppUser, AppError>? signInEmailResult;
  Result<AppUser, AppError>? signInWithIdTokenResult;
  Result<AppUser, AppError>? linkWithIdTokenResult;
  Result<AppUser, AppError>? webOAuthResult;
  Result<AppUser, AppError>? upgradeEmailResult;
  Result<AppUser?, AppError>? getSessionResult;
  Result<void, AppError> requestPasswordResetResult = const Result.success(
    null,
  );
  Result<void, AppError> resetPasswordResult = const Result.success(null);
  Result<void, AppError> sendVerificationEmailResult = const Result.success(
    null,
  );

  /// When set, [webOAuth] waits for it while the "browser" is showing.
  Completer<void>? browserHold;

  /// When set, [webOAuth] waits for it after the browser closed (callback
  /// exchange).
  Completer<void>? exchangeHold;

  /// False: [signUpEmail] returns the user but no session (verification
  /// required), so the current session stays.
  bool signUpReturnsSession = true;

  /// The user a successful sign-in / link returns when no result is scripted.
  AppUser signInUser = memberUser();

  /// Replaces the current user without an event.
  set user(AppUser? value) => _user = value;

  /// Emits [event] as the real client would.
  void emit(AuthEvent event) => _events.add(event);

  Future<void> close() => _events.close();

  @override
  Stream<AuthEvent> get events => _events.stream;

  @override
  AppUser? get currentUser => _user;

  @override
  Future<void> restore() async {}

  @override
  Future<String?> sessionToken() async => _user == null ? null : 'token';

  Result<AppUser, AppError> _apply(
    Result<AppUser, AppError>? scripted,
    AppUser fallback,
    AuthEvent event,
  ) {
    final result = scripted ?? Result.success(fallback);
    if (result case Success(data: final user)) {
      _user = user;
      emit(event);
    }
    return result;
  }

  AppUser _linked(String provider) {
    final current = _user ?? guestUser();
    return AppUser(
      id: current.id,
      email: signInUser.email,
      emailVerified: signInUser.emailVerified,
      providers: {...current.providers, provider}.toList(),
      name: signInUser.name,
      createdAt: current.createdAt,
    );
  }

  @override
  Future<Result<AppUser, AppError>> signInAnonymously() async {
    calls.add('signInAnonymously');
    return _apply(signInAnonymouslyResult, guestUser(), AuthEvent.signedIn);
  }

  @override
  Future<Result<AppUser, AppError>> signUpEmail(
    String email,
    String password, {
    String? name,
  }) async {
    calls.add('signUpEmail:$email');
    if (!signUpReturnsSession) {
      return signUpEmailResult ??
          Result.success(memberUser('new', email, const ['email']));
    }
    return _apply(
      signUpEmailResult,
      memberUser('new', email, const ['email']),
      AuthEvent.signedIn,
    );
  }

  @override
  Future<Result<AppUser, AppError>> signInEmail(
    String email,
    String password,
  ) async {
    calls.add('signInEmail:$email');
    return _apply(signInEmailResult, signInUser, AuthEvent.signedIn);
  }

  @override
  Future<Result<AppUser, AppError>> signInWithIdToken({
    required String provider,
    required String idToken,
    String? nonce,
    String? accessToken,
  }) async {
    calls.add('signInWithIdToken:$provider:$idToken');
    return _apply(signInWithIdTokenResult, signInUser, AuthEvent.signedIn);
  }

  @override
  Future<Result<AppUser, AppError>> linkWithIdToken({
    required String provider,
    required String idToken,
    String? nonce,
    String? accessToken,
  }) async {
    calls.add('linkWithIdToken:$provider:$idToken');
    return _apply(
      linkWithIdTokenResult,
      _linked(provider),
      AuthEvent.userUpdated,
    );
  }

  @override
  Future<Result<AppUser, AppError>> webOAuth(
    String provider, {
    bool link = false,
    void Function()? onBrowserClosed,
  }) async {
    calls.add('webOAuth:$provider:${link ? 'link' : 'signIn'}');
    try {
      await browserHold?.future;
    } on Object catch (e) {
      onBrowserClosed?.call();
      return e is AppError
          ? Result.failure(e)
          : const Result.failure(AppError.cancelled());
    }
    onBrowserClosed?.call();
    await exchangeHold?.future;
    return _apply(
      webOAuthResult,
      link ? _linked(provider) : signInUser,
      link ? AuthEvent.userUpdated : AuthEvent.signedIn,
    );
  }

  @override
  Future<Result<AppUser, AppError>> upgradeEmail(
    String email,
    String password,
  ) async {
    calls.add('upgradeEmail:$email');
    final current = _user ?? guestUser();
    return _apply(
      upgradeEmailResult,
      AppUser(
        id: current.id,
        email: email,
        providers: const ['email'],
        createdAt: current.createdAt,
      ),
      AuthEvent.userUpdated,
    );
  }

  @override
  Future<Result<AppUser?, AppError>> getSession() async {
    calls.add('getSession');
    final result = getSessionResult ?? Result.success(_user);
    if (result case Success(data: final user)) _user = user;
    return result;
  }

  @override
  Future<String?> freshJwt({bool force = false}) async =>
      _user == null ? null : 'jwt';

  @override
  Future<Result<void, AppError>> signOut() async {
    calls.add('signOut');
    _user = null;
    emit(AuthEvent.signedOut);
    return const Result.success(null);
  }

  @override
  Future<Result<void, AppError>> requestPasswordReset(
    String email, {
    String? redirectTo,
  }) async {
    calls.add('requestPasswordReset:$email');
    return requestPasswordResetResult;
  }

  @override
  Future<Result<void, AppError>> resetPassword(
    String token,
    String newPassword,
  ) async {
    calls.add('resetPassword:$token:$newPassword');
    return resetPasswordResult;
  }

  @override
  Future<Result<void, AppError>> sendVerificationEmail({
    String? email,
    String? callbackURL,
  }) async {
    calls.add('sendVerificationEmail:$email');
    return sendVerificationEmailResult;
  }

  @override
  void notifyPasswordRecovery() => emit(AuthEvent.passwordRecovery);

  @override
  Future<void> dispose() => close();
}
