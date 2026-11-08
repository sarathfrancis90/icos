import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icos/core/backend/backend_providers.dart';
import 'package:icos/core/utils/app_error.dart';
import 'package:icos/core/utils/result.dart';
import 'package:icos/features/auth/domain/auth_strategy.dart';
import 'package:icos/features/auth/providers/auth_provider.dart';

import '../../helpers/auth_test_harness.dart';
import '../../helpers/fake_auth_client.dart';
import '../../helpers/test_helpers.dart';

// The provider table (design §7.1/§7.2): iOS Google/Apple and Android Google
// use the native ID token; Android Apple runs the web flow. A guest links
// (same user id); a conflict offers the existing account, which is signed in
// with the guest bearer (the AuthClient sends it) so the server drops the
// guest.

void main() {
  setUpTestEnvironment();

  late FakeAuthClient client;
  late FakeNativeSignIn native;
  late ProviderContainer container;

  Future<AuthNotifier> start(AppUser? user, AuthPlatform platform) async {
    AuthNotifier.platformOverride = platform;
    addTearDown(() => AuthNotifier.platformOverride = null);
    client = FakeAuthClient(user: user);
    native = FakeNativeSignIn();
    addTearDown(client.close);
    container = ProviderContainer(
      overrides: authClientOverrides(
        client,
        native: native,
        config: authTestConfig,
      ),
    );
    addTearDown(container.dispose);
    await container.read(backendConfigProvider.future);
    container.listen(authNotifierProvider, (_, _) {});
    return container.read(authNotifierProvider.notifier);
  }

  group('guest upgrade keeps the user id', () {
    test('iOS Apple: native ID token, linked', () async {
      final outcome = await (await start(
        guestUser(),
        AuthPlatform.ios,
      )).signInWithApple();
      expect(native.calls, ['apple']);
      expect(client.calls, ['linkWithIdToken:apple:apple-token']);
      expect((outcome as AuthSuccess).accountLinked, isTrue);
      expect(outcome.user?.id, 'g');
      expect(container.read(authNotifierProvider).valueOrNull?.id, 'g');
    });

    test('iOS Google: native ID token, linked', () async {
      final outcome = await (await start(
        guestUser(),
        AuthPlatform.ios,
      )).signInWithGoogle();
      expect(native.calls, ['google']);
      expect(client.calls, ['linkWithIdToken:google:google-token']);
      expect((outcome as AuthSuccess).user?.id, 'g');
    });

    test('Android Google: native ID token, linked', () async {
      await (await start(guestUser(), AuthPlatform.android)).signInWithGoogle();
      expect(client.calls, ['linkWithIdToken:google:google-token']);
    });

    test('Android Apple: web flow with link, never native', () async {
      final outcome = await (await start(
        guestUser(),
        AuthPlatform.android,
      )).signInWithApple();
      expect(native.calls, isEmpty);
      expect(client.calls, ['webOAuth:apple:link']);
      expect((outcome as AuthSuccess).user?.id, 'g');
    });
  });

  group('signed-in or no session: sign-in', () {
    test('iOS Apple: native ID token sign-in', () async {
      await (await start(memberUser(), AuthPlatform.ios)).signInWithApple();
      expect(client.calls, ['signInWithIdToken:apple:apple-token']);
    });

    test('Android Apple: web sign-in', () async {
      await (await start(null, AuthPlatform.android)).signInWithApple();
      expect(native.calls, isEmpty);
      expect(client.calls, ['webOAuth:apple:signIn']);
    });
  });

  group('identity already belongs to another account', () {
    test('a link conflict is AuthIdentityExists for that provider', () async {
      final notifier = await start(guestUser(), AuthPlatform.ios);
      client.linkWithIdTokenResult = const Result.failure(
        AppError.conflict('Account already linked to a different user'),
      );
      final outcome = await notifier.signInWithGoogle();
      expect(outcome, isA<AuthIdentityExists>());
      expect((outcome as AuthIdentityExists).provider, OAuthKind.google);
      expect(
        container.read(authNotifierProvider).valueOrNull?.id,
        'g',
        reason: 'the guest is kept until the player chooses',
      );
    });

    test('a web link conflict (Android Apple) is AuthIdentityExists', () async {
      final notifier = await start(guestUser(), AuthPlatform.android);
      client.webOAuthResult = const Result.failure(
        AppError.conflict('Account already linked to a different user'),
      );
      expect(await notifier.signInWithApple(), isA<AuthIdentityExists>());
    });

    test('"Sign in anyway" signs in (no link) with the native token', () async {
      final notifier = await start(guestUser(), AuthPlatform.ios);
      final outcome = await notifier.signInToExistingWithOAuth(
        OAuthKind.google,
      );
      expect(client.calls, ['signInWithIdToken:google:google-token']);
      expect(outcome, isA<AuthSuccess>());
      expect((outcome as AuthSuccess).accountLinked, isFalse);
      expect(container.read(authNotifierProvider).valueOrNull?.id, 'u');
    });

    test(
      '"Sign in anyway" with Apple on Android uses the web sign-in',
      () async {
        final notifier = await start(guestUser(), AuthPlatform.android);
        await notifier.signInToExistingWithOAuth(OAuthKind.apple);
        expect(client.calls, ['webOAuth:apple:signIn']);
      },
    );

    test('a cancelled "Sign in anyway" leaves the guest', () async {
      final notifier = await start(guestUser(), AuthPlatform.ios);
      client.signInWithIdTokenResult = const Result.failure(
        AppError.cancelled(),
      );
      final outcome = await notifier.signInToExistingWithOAuth(
        OAuthKind.google,
      );
      expect(outcome, isA<AuthCancelled>());
      expect(container.read(authNotifierProvider).valueOrNull?.id, 'g');
      expect(client.calls, isNot(contains('signInAnonymously')));
    });
  });

  test('a native SDK without an ID token is a failure', () async {
    final notifier = await start(guestUser(), AuthPlatform.ios);
    native.appleToken = null;
    expect(await notifier.signInWithApple(), isA<AuthFailure>());
    expect(client.calls, isEmpty);
  });

  test('without Google client ids Google falls back to the web flow', () async {
    AuthNotifier.platformOverride = AuthPlatform.ios;
    addTearDown(() => AuthNotifier.platformOverride = null);
    client = FakeAuthClient(user: guestUser());
    addTearDown(client.close);
    container = ProviderContainer(overrides: authClientOverrides(client));
    addTearDown(container.dispose);
    await container.read(backendConfigProvider.future);
    container.listen(authNotifierProvider, (_, _) {});
    await container.read(authNotifierProvider.notifier).signInWithGoogle();
    expect(client.calls, ['webOAuth:google:link']);
  });

  group('email', () {
    test('a guest creating an account is upgraded in place', () async {
      final notifier = await start(guestUser(), AuthPlatform.ios);
      final outcome = await notifier.signUpWithEmail('a@b.co', 'secret1');
      expect(client.calls, ['upgradeEmail:a@b.co']);
      expect((outcome as AuthSuccess).isNewAccount, isTrue);
      expect(outcome.user?.id, 'g');
    });

    test('an email that already has an account offers sign-in', () async {
      final notifier = await start(guestUser(), AuthPlatform.ios);
      client.upgradeEmailResult = const Result.failure(
        AppError.conflict('Email already exists'),
      );
      final outcome = await notifier.signUpWithEmail('a@b.co', 'secret1');
      expect(outcome, isA<AuthIdentityExists>());
      expect((outcome as AuthIdentityExists).email, 'a@b.co');
    });

    test('no session: a fresh sign-up', () async {
      final notifier = await start(null, AuthPlatform.ios);
      final outcome = await notifier.signUpWithEmail('a@b.co', 'secret1');
      expect(client.calls, ['signUpEmail:a@b.co']);
      expect((outcome as AuthSuccess).isNewAccount, isTrue);
    });

    test(
      'a sign-up that returned no session asks to confirm the email',
      () async {
        final notifier = await start(memberUser('old'), AuthPlatform.ios);
        // The server answered with the new user but no token: the client kept
        // the previous session.
        client.signUpReturnsSession = false;
        final outcome = await notifier.signUpWithEmail('a@b.co', 'secret1');
        expect(outcome, isA<AuthEmailConfirmationRequired>());
        expect((outcome as AuthEmailConfirmationRequired).fromSignUp, isTrue);
      },
    );

    test('a wrong password is a friendly failure', () async {
      final notifier = await start(guestUser(), AuthPlatform.ios);
      client.signInEmailResult = const Result.failure(
        AppError.auth('Invalid email or password'),
      );
      final outcome = await notifier.signInWithEmail('a@b.co', 'nope');
      expect(
        (outcome as AuthFailure).message,
        'Invalid email or password. Please try again.',
      );
    });

    test('resend sends the verification email to that address', () async {
      final notifier = await start(memberUser(), AuthPlatform.ios);
      await notifier.resendConfirmation('a@b.co', fromSignUp: true);
      expect(client.calls, ['sendVerificationEmail:a@b.co']);
    });
  });

  group('password reset', () {
    test('request: an unknown address is neutral, rate limit is not', () async {
      final notifier = await start(memberUser(), AuthPlatform.ios);
      client.requestPasswordResetResult = const Result.failure(
        AppError.notFound('User not found'),
      );
      expect(await notifier.sendPasswordReset('x@y.z'), isA<Success>());
      client.requestPasswordResetResult = const Result.failure(
        AppError.rateLimit('slow down'),
      );
      final limited = await notifier.sendPasswordReset('x@y.z');
      expect((limited as Failure).error, isA<RateLimitError>());
    });

    test('the new password is sent with the token from the link', () async {
      final notifier = await start(memberUser(), AuthPlatform.ios);
      container.read(passwordRecoveryPendingProvider.notifier).start('tok-1');
      expect(await notifier.updatePassword('hunter22'), isA<Success>());
      expect(client.calls, ['resetPassword:tok-1:hunter22']);
    });

    test('an invalid token is reported as an expired link', () async {
      final notifier = await start(memberUser(), AuthPlatform.ios);
      container.read(passwordRecoveryPendingProvider.notifier).start('tok-1');
      client.resetPasswordResult = const Result.failure(
        AppError.validation('Invalid token'),
      );
      final result = await notifier.updatePassword('hunter22');
      expect(
        (result as Failure).error,
        const AppError.auth(AuthStrategy.recoverySessionExpiredMessage),
      );
    });

    test('no token at all is an expired link, nothing sent', () async {
      final notifier = await start(memberUser(), AuthPlatform.ios);
      final result = await notifier.updatePassword('hunter22');
      expect(
        (result as Failure).error,
        const AppError.auth(AuthStrategy.recoverySessionExpiredMessage),
      );
      expect(client.calls, isEmpty);
    });
  });

  test('sign-out clears the session and starts a new guest', () async {
    final notifier = await start(memberUser(), AuthPlatform.ios);
    await notifier.signOut();
    expect(client.calls, ['signOut', 'signInAnonymously']);
    expect(
      container.read(authNotifierProvider).valueOrNull?.isAnonymous,
      isTrue,
    );
  });

  test('auth events from the client update the state', () async {
    await start(null, AuthPlatform.ios);
    client.user = memberUser();
    client.emit(AuthEvent.signedIn);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(authNotifierProvider).valueOrNull?.id, 'u');
    expect(container.read(isGuestProvider), isFalse);
  });
}
