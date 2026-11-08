import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:icos/core/backend/auth_event.dart';
import 'package:icos/core/services/storage_service.dart';
import 'package:icos/features/auth/domain/auth_strategy.dart';
import 'package:icos/features/auth/presentation/widgets/auth_outcome_handler.dart';
import 'package:icos/features/auth/providers/auth_provider.dart';
import 'package:icos/features/groups/domain/pending_invite.dart';

import '../../helpers/auth_test_harness.dart';
import '../../helpers/fake_auth_client.dart';
import '../../helpers/storage_test_helpers.dart';
import '../../helpers/test_helpers.dart';

// A web sign-in that has finished must read as finished: one message, and the
// auth screen is left, exactly like the native paths.

AppUser? _current;

/// The event the exchange emits again a tick after the call returned, as a
/// real stream may (the worst case for a duplicate announcement).
AuthEvent _lateEvent = AuthEvent.signedIn;
final flowMessages = <String>[];

late ProviderContainer _container;
late FakeAuthClient _client;

void main() {
  setUpTestEnvironment();

  late Directory dir;
  setUp(() async {
    dir = await initTestStorage();
    // These tests are about the continuation, not the name prompt.
    await StorageService.setDisplayNamePromptShown('g');
    await StorageService.setDisplayNamePromptShown('u');
    AuthNotifier.platformOverride = AuthPlatform.ios;
  });
  tearDown(() async {
    AuthNotifier.platformOverride = null;
    await dir.delete(recursive: true);
  });

  Future<GoRouter> pump(WidgetTester tester) async {
    _client = FakeAuthClient(user: _current);
    addTearDown(_client.close);
    var echoed = false;
    _client.events.listen((e) {
      if (e == AuthEvent.signedOut || echoed) return;
      echoed = true;
      Future<void>.delayed(Duration.zero, () => _client.emit(_lateEvent));
    });
    _container = ProviderContainer(overrides: authClientOverrides(_client));
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
    _current = guestUser();
    _lateEvent = AuthEvent.userUpdated; // worst case: the old duplicate
    final router = await pump(tester);

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(_client.calls, hasLength(1));
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
    _lateEvent = AuthEvent.signedIn;
    final router = await pump(tester);

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(_client.calls, hasLength(1));
    expect(flowMessages, isEmpty, reason: 'no second announcement');
    expect(find.text('Signed in.'), findsOneWidget);
    expect(at(router), '/');
  });

  testWidgets('guest with a pending invite lands on the invite', (
    tester,
  ) async {
    _current = guestUser();
    _lateEvent = AuthEvent.signedIn;
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
