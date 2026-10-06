import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icos/features/auth/data/oauth_web_gateway.dart';
import 'package:icos/features/auth/domain/auth_strategy.dart';
import 'package:icos/features/auth/providers/auth_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../helpers/test_helpers.dart';

// Apple App Review, Guideline 4 (Design), build 1.0.0 (4): signing in must
// not send people to the default browser. Every web OAuth page opens in the
// in-app browser (Safari View Controller / Custom Tab).

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
  final modes = <LaunchMode>[];
  final authorizeCalls = <({OAuthProvider provider, bool link})>[];
  int closeCalls = 0;
  Completer<bool>? hold;

  @override
  Future<Uri> authorizeUrl(
    OAuthProvider provider, {
    required bool link,
    required String redirectTo,
  }) async {
    authorizeCalls.add((provider: provider, link: link));
    return Uri.parse('https://example.test/authorize');
  }

  @override
  Future<bool> launch(Uri url, LaunchMode mode) {
    modes.add(mode);
    return hold?.future ?? Future.value(true);
  }

  @override
  Future<void> close() async => closeCalls++;
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

  setUp(() {
    gateway = _FakeGateway();
    OAuthWebGateway.current = gateway;
  });
  tearDown(() {
    OAuthWebGateway.current = const OAuthWebGateway();
    AuthNotifier.platformOverride = null;
  });

  test('the launch mode is the in-app browser, never the system browser', () {
    expect(OAuthWebGateway.launchMode, LaunchMode.inAppBrowserView);
  });

  group('every web OAuth launch opens in the app', () {
    for (final platform in [AuthPlatform.ios, AuthPlatform.android]) {
      test('linkIdentity (guest) with Google on ${platform.name}', () async {
        AuthNotifier.platformOverride = platform;
        final outcome = await start(_guest).signInWithGoogle();
        expect(outcome, isA<AuthRedirected>());
        expect(gateway.authorizeCalls.single.link, isTrue);
        expect(gateway.authorizeCalls.single.provider, OAuthProvider.google);
        expect(gateway.modes, [LaunchMode.inAppBrowserView]);
      });

      test(
        'signInWithOAuth (no guest) with Google on ${platform.name}',
        () async {
          AuthNotifier.platformOverride = platform;
          final outcome = await start(_member).signInWithGoogle();
          expect(outcome, isA<AuthRedirected>());
          expect(gateway.authorizeCalls.single.link, isFalse);
          expect(gateway.modes, [LaunchMode.inAppBrowserView]);
        },
      );
    }

    test('linkIdentity (guest) with Apple on Android', () async {
      AuthNotifier.platformOverride = AuthPlatform.android;
      final outcome = await start(_guest).signInWithApple();
      expect(outcome, isA<AuthRedirected>());
      expect(gateway.authorizeCalls.single.link, isTrue);
      expect(gateway.authorizeCalls.single.provider, OAuthProvider.apple);
      expect(gateway.modes, [LaunchMode.inAppBrowserView]);
    });

    test('signInWithOAuth with Apple on Android', () async {
      AuthNotifier.platformOverride = AuthPlatform.android;
      await start(_member).signInWithApple();
      expect(gateway.authorizeCalls.single.link, isFalse);
      expect(gateway.modes, [LaunchMode.inAppBrowserView]);
    });

    test(
      'a page that cannot be shown is a failure, not a stuck spinner',
      () async {
        AuthNotifier.platformOverride = AuthPlatform.ios;
        gateway.hold = Completer<bool>()..complete(false);
        final notifier = start(_guest);
        final outcome = await notifier.signInWithGoogle();
        expect(outcome, isA<AuthFailure>());
        expect(container.read(authNotifierProvider).isLoading, isFalse);
      },
    );
  });

  group('the in-app browser is dismissed by the callback', () {
    test(
      'closeInAppWebView runs once when the linked session arrives',
      () async {
        AuthNotifier.platformOverride = AuthPlatform.ios;
        final notifier = start(_guest);
        await notifier.signInWithGoogle();
        expect(gateway.closeCalls, 0);

        final linked = AuthState(
          AuthChangeEvent.userUpdated,
          Session(accessToken: 't', tokenType: 'bearer', user: _member),
        );
        notifier.handleAuthEvent(linked);
        notifier.handleAuthEvent(linked);
        expect(gateway.closeCalls, 1);
      },
    );

    test('an event with no web flow open does not close anything', () {
      final notifier = start(_guest);
      notifier.handleAuthEvent(
        AuthState(
          AuthChangeEvent.signedIn,
          Session(accessToken: 't', tokenType: 'bearer', user: _member),
        ),
      );
      expect(gateway.closeCalls, 0);
    });
  });

  group('closing the in-app browser without finishing', () {
    test('resuming without a new session clears the busy state', () async {
      AuthNotifier.platformOverride = AuthPlatform.ios;
      gateway.hold = Completer<bool>();
      final notifier = start(_guest);
      final pending = notifier.signInWithGoogle();
      await Future<void>.delayed(Duration.zero);
      expect(container.read(authNotifierProvider).isLoading, isTrue);

      notifier.handleAppResumed();

      final state = container.read(authNotifierProvider);
      expect(state.isLoading, isFalse);
      // The guest session is intact.
      expect(state.valueOrNull?.id, 'g');
      expect(state.valueOrNull?.isAnonymous, isTrue);

      gateway.hold!.complete(true);
      await pending;
    });

    test(
      'the lifecycle observer calls it on AppLifecycleState.resumed',
      () async {
        AuthNotifier.platformOverride = AuthPlatform.ios;
        gateway.hold = Completer<bool>();
        final notifier = start(_guest);
        final pending = notifier.signInWithGoogle();
        await Future<void>.delayed(Duration.zero);
        expect(container.read(authNotifierProvider).isLoading, isTrue);

        TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
          AppLifecycleState.paused,
        );
        expect(container.read(authNotifierProvider).isLoading, isTrue);
        TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        expect(container.read(authNotifierProvider).isLoading, isFalse);

        gateway.hold!.complete(true);
        await pending;
      },
    );

    test('resume does not touch an unrelated busy state', () {
      final notifier = start(_guest);
      // No web flow open.
      expect(() => notifier.handleAppResumed(), returnsNormally);
      expect(container.read(authNotifierProvider).isLoading, isFalse);
    });
  });
}
