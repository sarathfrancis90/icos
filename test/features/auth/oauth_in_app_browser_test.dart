import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icos/core/backend/backend_config.dart';
import 'package:icos/core/backend/backend_providers.dart';
import 'package:icos/core/utils/app_error.dart';
import 'package:icos/core/utils/result.dart';
import 'package:icos/features/auth/domain/auth_strategy.dart';
import 'package:icos/features/auth/providers/auth_provider.dart';

import '../../helpers/auth_test_harness.dart';
import '../../helpers/fake_auth_client.dart';
import '../../helpers/test_helpers.dart';

// Apple App Review, Guideline 4 (Design), build 1.0.0 (4): signing in must
// not send people to the default browser. Every web OAuth page runs in the
// platform authentication session (ASWebAuthenticationSession / Custom Tab),
// through `AuthClient.webOAuth`.

void main() {
  setUpTestEnvironment();

  late FakeAuthClient client;
  late ProviderContainer container;

  Future<AuthNotifier> start(AppUser? user) async {
    client = FakeAuthClient(user: user);
    addTearDown(client.close);
    container = ProviderContainer(
      // No Google client ids: Google runs the web flow on every platform.
      overrides: authClientOverrides(client),
    );
    addTearDown(container.dispose);
    await container.read(backendConfigProvider.future);
    // Keep the auto-dispose notifier alive while the test runs.
    container.listen(authNotifierProvider, (_, _) {});
    return container.read(authNotifierProvider.notifier);
  }

  bool loading() => container.read(authNotifierProvider).isLoading;

  setUp(() {
    AuthNotifier.resumeGrace = const Duration(milliseconds: 30);
    AuthNotifier.platformOverride = AuthPlatform.ios;
  });
  tearDown(() {
    AuthNotifier.resumeGrace = const Duration(seconds: 1);
    AuthNotifier.platformOverride = null;
  });

  test('the session API is told the callback scheme', () {
    expect(kOAuthRedirectUri, kOAuthCallbackUrl);
    expect(Uri.parse(kOAuthRedirectUri).scheme, kOAuthCallbackScheme);
    expect(kOAuthCallbackScheme, 'io.icos');
  });

  group('every web OAuth launch goes through the session API', () {
    for (final platform in [AuthPlatform.ios, AuthPlatform.android]) {
      test('link (guest) with Google on ${platform.name}', () async {
        AuthNotifier.platformOverride = platform;
        final outcome = await (await start(guestUser())).signInWithGoogle();
        expect(outcome, isA<AuthSuccess>());
        expect((outcome as AuthSuccess).accountLinked, isTrue);
        expect(outcome.user?.id, 'g', reason: 'the guest id is kept');
        expect(client.calls, ['webOAuth:google:link']);
      });

      test('sign-in (no guest) with Google on ${platform.name}', () async {
        AuthNotifier.platformOverride = platform;
        final outcome = await (await start(memberUser())).signInWithGoogle();
        expect(outcome, isA<AuthSuccess>());
        expect(client.calls, ['webOAuth:google:signIn']);
      });
    }

    test('link (guest) and sign-in with Apple on Android', () async {
      AuthNotifier.platformOverride = AuthPlatform.android;
      await (await start(guestUser())).signInWithApple();
      expect(client.calls, ['webOAuth:apple:link']);
      await (await start(memberUser())).signInWithApple();
      expect(client.calls, ['webOAuth:apple:signIn']);
    });
  });

  group('outcomes', () {
    test('success: one web flow, busy cleared', () async {
      final notifier = await start(guestUser());
      final outcome = await notifier.signInWithGoogle();
      expect(outcome, isA<AuthSuccess>());
      expect(client.calls, hasLength(1));
      expect(loading(), isFalse);
    });

    test('cancel is AuthCancelled, guest kept, busy cleared', () async {
      final notifier = await start(guestUser());
      client.webOAuthResult = const Result.failure(AppError.cancelled());
      final outcome = await notifier.signInWithGoogle();
      expect(outcome, isA<AuthCancelled>());
      expect(loading(), isFalse);
      expect(container.read(authNotifierProvider).valueOrNull?.id, 'g');
    });

    test('failure before launch is AuthFailure, busy cleared', () async {
      final notifier = await start(guestUser());
      client.webOAuthResult = const Result.failure(
        AppError.network('No internet connection'),
      );
      final outcome = await notifier.signInWithGoogle();
      expect(outcome, isA<AuthFailure>());
      expect(loading(), isFalse);
    });

    test(
      'failure during launch is AuthFailure (not cancelled), busy cleared',
      () async {
        final notifier = await start(guestUser());
        client.webOAuthResult = const Result.failure(
          AppError.auth('boom https://fn.example.test/auth/x?state=SECRET'),
        );
        final outcome = await notifier.signInWithGoogle();
        expect(outcome, isA<AuthFailure>());
        expect((outcome as AuthFailure).message, isNot(contains('SECRET')));
        expect(loading(), isFalse);
      },
    );

    test(
      'an unexpected launch error never leaks the URL to the user',
      () async {
        final notifier = await start(guestUser());
        client.webOAuthResult = const Result.failure(
          AppError.unknown('bad https://x.test/authorize?state=SECRET'),
        );
        final failed = await notifier.signInWithGoogle();
        expect(failed, isA<AuthFailure>());
        expect((failed as AuthFailure).message, isNot(contains('SECRET')));
      },
    );

    test('identity already linked offers sign-in instead', () async {
      final notifier = await start(guestUser());
      client.webOAuthResult = const Result.failure(
        AppError.conflict('Account already linked to a different user'),
      );
      final outcome = await notifier.signInWithGoogle();
      expect(outcome, isA<AuthIdentityExists>());
      expect((outcome as AuthIdentityExists).provider, OAuthKind.google);
      expect(loading(), isFalse);
    });
  });

  group('closing the sheet without finishing', () {
    test('resuming without a new session clears the busy state', () async {
      final notifier = await start(guestUser());
      client.browserHold = Completer<void>();
      final pending = notifier.signInWithGoogle();
      await Future<void>.delayed(Duration.zero);
      expect(loading(), isTrue);

      notifier.handleAppResumed();
      // A resume alone is not abandonment: the spinner stays for the grace.
      expect(loading(), isTrue);
      await Future<void>.delayed(AuthNotifier.resumeGrace * 2);

      final state = container.read(authNotifierProvider);
      expect(state.isLoading, isFalse);
      // The guest session is intact.
      expect(state.valueOrNull?.id, 'g');
      expect(state.valueOrNull?.isAnonymous, isTrue);

      client.browserHold!.completeError(const AppError.cancelled());
      expect(await pending, isA<AuthCancelled>());
    });

    test(
      'the lifecycle observer calls it on AppLifecycleState.resumed',
      () async {
        final notifier = await start(guestUser());
        client.browserHold = Completer<void>();
        final pending = notifier.signInWithGoogle();
        await Future<void>.delayed(Duration.zero);
        expect(loading(), isTrue);

        TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
          AppLifecycleState.paused,
        );
        expect(loading(), isTrue);
        TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        expect(loading(), isTrue);
        await Future<void>.delayed(AuthNotifier.resumeGrace * 2);
        expect(loading(), isFalse);

        client.browserHold!.completeError(const AppError.cancelled());
        await pending;
      },
    );

    test(
      'a resume that is followed by the sheet finishing never flickers',
      () async {
        final notifier = await start(guestUser());
        client.browserHold = Completer<void>();
        final pending = notifier.signInWithGoogle();
        await Future<void>.delayed(Duration.zero);
        notifier.handleAppResumed();
        // The sheet finishes inside the grace period.
        client.browserHold!.complete();
        await pending;
        expect(loading(), isFalse);
        await Future<void>.delayed(AuthNotifier.resumeGrace * 2);
        expect(loading(), isFalse);
      },
    );

    test('resume does not touch a busy state with no sheet showing', () async {
      // Callback is being exchanged: the sheet is gone, so resume must not
      // hide the spinner early.
      final notifier = await start(guestUser());
      client.exchangeHold = Completer<void>();
      final pending = notifier.signInWithGoogle();
      await Future<void>.delayed(Duration.zero);
      expect(loading(), isTrue);
      notifier.handleAppResumed();
      await Future<void>.delayed(AuthNotifier.resumeGrace * 2);
      expect(loading(), isTrue);
      client.exchangeHold!.complete();
      await pending;
      expect(loading(), isFalse);
    });
  });
}
