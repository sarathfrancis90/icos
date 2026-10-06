import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icos/features/auth/data/oauth_web_gateway.dart';
import 'package:icos/features/auth/domain/auth_strategy.dart';
import 'package:icos/features/auth/providers/auth_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/test_helpers.dart';

// Apple App Review, Guideline 4 (Design), build 1.0.0 (4): signing in must
// not send people to the default browser. Every web OAuth page runs in the
// platform authentication session (ASWebAuthenticationSession / Custom Tab).

const _guest = User(
  id: 'g',
  appMetadata: {},
  userMetadata: {},
  aud: 'authenticated',
  createdAt: '2026-10-05T00:00:00Z',
  isAnonymous: true,
);
const _member = User(
  id: 'u',
  appMetadata: {},
  userMetadata: {},
  aud: 'authenticated',
  createdAt: '2026-10-05T00:00:00Z',
);

class _FakeGateway extends OAuthWebGateway {
  final authorizeCalls =
      <({OAuthProvider provider, bool link, String redirect})>[];
  final authenticated = <Uri>[];
  final completed = <Uri>[];
  Object? authorizeError;
  Object? authenticateError;
  Object? completeError;
  Completer<Uri>? hold;

  @override
  Future<Uri> authorizeUrl(
    OAuthProvider provider, {
    required bool link,
    required String redirectTo,
  }) async {
    authorizeCalls.add((provider: provider, link: link, redirect: redirectTo));
    if (authorizeError != null) throw authorizeError!;
    return Uri.parse('https://example.test/authorize?state=s');
  }

  @override
  Future<Uri> authenticate(Uri url) {
    authenticated.add(url);
    if (authenticateError != null) throw authenticateError!;
    return hold?.future ??
        Future.value(Uri.parse('io.supabase.icos://oauth-callback?code=abc'));
  }

  @override
  Future<void> completeSession(Uri callback) async {
    completed.add(callback);
    if (completeError != null) throw completeError!;
  }
}

class _FakeAuth extends AuthNotifier {
  _FakeAuth(this._user);
  User? _user;

  @override
  User? get currentUser => _user;

  @override
  AsyncValue<User?> build() {
    attachLifecycleObserver();
    return AsyncValue.data(_user);
  }
}

void main() {
  setUpTestEnvironment();

  late _FakeGateway gateway;
  late ProviderContainer container;

  AuthNotifier start(User? user) {
    container = ProviderContainer(
      overrides: [authNotifierProvider.overrideWith(() => _FakeAuth(user))],
    );
    addTearDown(container.dispose);
    // Keep the auto-dispose notifier alive while the test runs.
    container.listen(authNotifierProvider, (_, _) {});
    return container.read(authNotifierProvider.notifier);
  }

  bool loading() => container.read(authNotifierProvider).isLoading;

  setUp(() {
    gateway = _FakeGateway();
    OAuthWebGateway.current = gateway;
    AuthNotifier.platformOverride = AuthPlatform.ios;
  });
  tearDown(() {
    OAuthWebGateway.current = const OAuthWebGateway();
    AuthNotifier.platformOverride = null;
  });

  test('the session API is told the callback scheme', () {
    expect(OAuthWebGateway.callbackScheme, 'io.supabase.icos');
    expect(Uri.parse(kOAuthRedirectUri).scheme, OAuthWebGateway.callbackScheme);
  });

  group('every web OAuth launch goes through the session API', () {
    for (final platform in [AuthPlatform.ios, AuthPlatform.android]) {
      test('linkIdentity (guest) with Google on ${platform.name}', () async {
        AuthNotifier.platformOverride = platform;
        final outcome = await start(_guest).signInWithGoogle();
        expect(outcome, isA<AuthRedirected>());
        expect(gateway.authorizeCalls.single.link, isTrue);
        expect(gateway.authorizeCalls.single.provider, OAuthProvider.google);
        expect(gateway.authorizeCalls.single.redirect, kOAuthRedirectUri);
        expect(gateway.authenticated, hasLength(1));
      });

      test(
        'signInWithOAuth (no guest) with Google on ${platform.name}',
        () async {
          AuthNotifier.platformOverride = platform;
          final outcome = await start(_member).signInWithGoogle();
          expect(outcome, isA<AuthRedirected>());
          expect(gateway.authorizeCalls.single.link, isFalse);
          expect(gateway.authenticated, hasLength(1));
        },
      );
    }

    test('linkIdentity (guest) and sign-in with Apple on Android', () async {
      AuthNotifier.platformOverride = AuthPlatform.android;
      await start(_guest).signInWithApple();
      expect(gateway.authorizeCalls.single.link, isTrue);
      expect(gateway.authorizeCalls.single.provider, OAuthProvider.apple);
      await start(_member).signInWithApple();
      expect(gateway.authorizeCalls.last.link, isFalse);
    });
  });

  group('outcomes', () {
    test(
      'success: the callback is processed exactly once, busy cleared',
      () async {
        final notifier = start(_guest);
        final outcome = await notifier.signInWithGoogle();
        expect(outcome, isA<AuthRedirected>());
        expect(gateway.completed, [
          Uri.parse('io.supabase.icos://oauth-callback?code=abc'),
        ]);
        expect(loading(), isFalse);
      },
    );

    test(
      'cancel (CANCELED) is AuthCancelled, guest kept, busy cleared',
      () async {
        gateway.authenticateError = PlatformException(
          code: 'CANCELED',
          message: 'User canceled login',
        );
        final notifier = start(_guest);
        final outcome = await notifier.signInWithGoogle();
        expect(outcome, isA<AuthCancelled>());
        expect(gateway.completed, isEmpty);
        expect(loading(), isFalse);
        expect(container.read(authNotifierProvider).valueOrNull?.id, 'g');
      },
    );

    test('failure before launch is AuthFailure, busy cleared', () async {
      gateway.authorizeError = const AuthException('network down');
      final outcome = await start(_guest).signInWithGoogle();
      expect(outcome, isA<AuthFailure>());
      expect(gateway.authenticated, isEmpty);
      expect(loading(), isFalse);
    });

    test(
      'failure during launch is AuthFailure (not cancelled), busy cleared',
      () async {
        gateway.authenticateError = PlatformException(
          code: 'FAILED',
          message: 'boom https://x.supabase.co/auth/v1/authorize?state=SECRET',
        );
        final outcome = await start(_guest).signInWithGoogle();
        expect(outcome, isA<AuthFailure>());
        expect((outcome as AuthFailure).message, isNot(contains('SECRET')));
        expect(gateway.completed, isEmpty);
        expect(loading(), isFalse);
      },
    );

    test(
      'an unexpected launch error never leaks the URL to the user',
      () async {
        gateway.authenticateError = StateError(
          'bad https://x.supabase.co/authorize?state=SECRET',
        );
        final outcome = await start(_guest).signInWithGoogle();
        expect(outcome, isA<AuthFailure>());
        expect((outcome as AuthFailure).message, isNot(contains('SECRET')));
      },
    );

    test(
      'identity already exists from the exchange offers sign-in instead',
      () async {
        gateway.completeError = const AuthException(
          'Identity is already linked to another user',
          code: 'identity_already_exists',
        );
        final outcome = await start(_guest).signInWithGoogle();
        expect(outcome, isA<AuthIdentityExists>());
        expect(loading(), isFalse);
      },
    );
  });

  group('closing the sheet without finishing', () {
    test('resuming without a new session clears the busy state', () async {
      gateway.hold = Completer<Uri>();
      final notifier = start(_guest);
      final pending = notifier.signInWithGoogle();
      await Future<void>.delayed(Duration.zero);
      expect(loading(), isTrue);

      notifier.handleAppResumed();

      final state = container.read(authNotifierProvider);
      expect(state.isLoading, isFalse);
      // The guest session is intact.
      expect(state.valueOrNull?.id, 'g');
      expect(state.valueOrNull?.isAnonymous, isTrue);

      gateway.hold!.completeError(PlatformException(code: 'CANCELED'));
      expect(await pending, isA<AuthCancelled>());
    });

    test(
      'the lifecycle observer calls it on AppLifecycleState.resumed',
      () async {
        gateway.hold = Completer<Uri>();
        final notifier = start(_guest);
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
        expect(loading(), isFalse);

        gateway.hold!.completeError(PlatformException(code: 'CANCELED'));
        await pending;
      },
    );

    test('resume does not touch a busy state with no sheet showing', () async {
      // Callback is being exchanged: the sheet is gone, so resume must not
      // hide the spinner early.
      final exchange = Completer<void>();
      final notifier = start(_guest);
      gateway.completeError = null;
      final slow = _SlowExchange(exchange.future);
      OAuthWebGateway.current = slow;
      final pending = notifier.signInWithGoogle();
      await Future<void>.delayed(Duration.zero);
      expect(loading(), isTrue);
      notifier.handleAppResumed();
      expect(loading(), isTrue);
      exchange.complete();
      await pending;
      expect(loading(), isFalse);
    });
  });
}

class _SlowExchange extends _FakeGateway {
  _SlowExchange(this._gate);
  final Future<void> _gate;

  @override
  Future<void> completeSession(Uri callback) => _gate;
}
