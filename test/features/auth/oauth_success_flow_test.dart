import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:icos/features/auth/data/oauth_web_gateway.dart';
import 'package:icos/features/auth/domain/auth_strategy.dart';
import 'package:icos/features/auth/presentation/widgets/auth_outcome_handler.dart';
import 'package:icos/features/auth/providers/auth_provider.dart';
import 'package:icos/features/groups/domain/pending_invite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/storage_test_helpers.dart';
import '../../helpers/test_helpers.dart';

// A web sign-in that has finished must read as finished: one message, and the
// auth screen is left, exactly like the native paths.

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

User? _current;
AuthChangeEvent _event = AuthChangeEvent.signedIn;
int _completed = 0;
final flowMessages = <String>[];

class _Gateway extends OAuthWebGateway {
  @override
  Future<Uri> authorizeUrl(
    OAuthProvider provider, {
    required bool link,
    required String redirectTo,
  }) async => Uri.parse('https://example.test/authorize');

  @override
  Future<Uri> authenticate(Uri url) async =>
      Uri.parse('io.supabase.icos://oauth-callback?code=abc');

  @override
  Future<void> completeSession(Uri callback) async {
    _completed++;
    _current = _member;
    // What the SDK does: the exchange emits an auth event. Delivered a tick
    // later, as a real stream would.
    final container = _container;
    Future<void>.delayed(
      Duration.zero,
      () => container
          .read(authNotifierProvider.notifier)
          .handleAuthEvent(
            AuthState(
              _event,
              Session(accessToken: 't', tokenType: 'bearer', user: _member),
            ),
          ),
    );
  }
}

late ProviderContainer _container;

class _FakeAuth extends AuthNotifier {
  @override
  User? get currentUser => _current;

  @override
  AsyncValue<User?> build() => AsyncValue.data(_current);
}

void main() {
  setUpTestEnvironment();

  late Directory dir;
  setUp(() async {
    dir = await initTestStorage();
    _completed = 0;
    OAuthWebGateway.current = _Gateway();
    AuthNotifier.platformOverride = AuthPlatform.ios;
  });
  tearDown(() async {
    OAuthWebGateway.current = const OAuthWebGateway();
    AuthNotifier.platformOverride = null;
    await dir.delete(recursive: true);
  });

  Future<GoRouter> pump(WidgetTester tester) async {
    _container = ProviderContainer(
      overrides: [authNotifierProvider.overrideWith(_FakeAuth.new)],
    );
    addTearDown(_container.dispose);
    _container.listen(authNotifierProvider, (_, _) {});
    // Anything the auth event handler itself would announce (the old
    // duplicate "Account linked").
    flowMessages.clear();
    _container.listen<String?>(authFlowMessageProvider, (_, m) {
      if (m != null) flowMessages.add(m);
    });
    final router = GoRouter(
      initialLocation: '/auth',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('home')),
        ),
        GoRoute(
          path: '/join/:code',
          builder: (_, _) => const Scaffold(body: Text('join')),
        ),
        GoRoute(
          path: '/auth',
          builder: (_, _) => Consumer(
            builder: (context, ref, _) {
              listenForAuthFlowMessages(context, ref);
              return Scaffold(
                body: TextButton(
                  onPressed: () async {
                    final outcome = await ref
                        .read(authNotifierProvider.notifier)
                        .signInWithGoogle();
                    if (context.mounted) {
                      await handleAuthOutcome(context, ref, outcome);
                    }
                  },
                  child: const Text('go'),
                ),
              );
            },
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: _container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    return router;
  }

  String at(GoRouter r) =>
      r.routerDelegate.currentConfiguration.last.matchedLocation;

  testWidgets('guest: "Account linked" once, then home', (tester) async {
    _current = _guest;
    _event = AuthChangeEvent.userUpdated; // worst case: the old duplicate
    final router = await pump(tester);

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(_completed, 1);
    expect(flowMessages, isEmpty, reason: 'no second announcement');
    expect(
      find.text('Account linked. Your progress is saved.'),
      findsOneWidget,
    );
    expect(find.textContaining('window that just opened'), findsNothing);
    expect(at(router), '/');
  });

  testWidgets('signed-out: "Signed in." once, then home', (tester) async {
    _current = null;
    _event = AuthChangeEvent.signedIn;
    final router = await pump(tester);

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(_completed, 1);
    expect(flowMessages, isEmpty, reason: 'no second announcement');
    expect(find.text('Signed in.'), findsOneWidget);
    expect(at(router), '/');
  });

  testWidgets('guest with a pending invite lands on the invite', (
    tester,
  ) async {
    _current = _guest;
    _event = AuthChangeEvent.signedIn;
    await PendingInvite.save('ABC123');
    final router = await pump(tester);

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(
      find.text('Account linked. Your progress is saved.'),
      findsOneWidget,
    );
    expect(at(router), '/join/ABC123');
  });
}
