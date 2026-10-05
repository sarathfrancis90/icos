import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:icos/core/router/deep_link.dart';
import 'package:icos/core/router/invite_continuation.dart';
import 'package:icos/core/services/storage_service.dart';
import 'package:icos/features/auth/providers/auth_provider.dart';
import 'package:icos/features/groups/domain/pending_invite.dart';
import 'package:icos/features/groups/presentation/join_group_screen.dart';
import 'package:icos/features/groups/providers/groups_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/storage_test_helpers.dart';
import '../../helpers/test_helpers.dart';

class _FakeAuth extends AuthNotifier {
  @override
  AsyncValue<User?> build() => const AsyncValue.data(null);
}

const _member = User(
  id: 'u',
  appMetadata: {},
  userMetadata: {},
  aud: 'authenticated',
  createdAt: '2026-10-05T00:00:00Z',
);
const _guest = User(
  id: 'g',
  appMetadata: {},
  userMetadata: {},
  aud: 'authenticated',
  createdAt: '2026-10-05T00:00:00Z',
  isAnonymous: true,
);

AuthState _event(AuthChangeEvent e, User user) =>
    AuthState(e, Session(accessToken: 't', tokenType: 'bearer', user: user));

/// A router wired the way the app's is.
final _routerProvider = Provider<GoRouter>((ref) {
  final r = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => const SizedBox()),
      GoRoute(path: '/join/:code', builder: (_, _) => const SizedBox()),
    ],
  );
  wireInviteContinuation(ref, r);
  return r;
});

String _at(GoRouter r) =>
    r.routerDelegate.currentConfiguration.last.matchedLocation;

void main() {
  setUpTestEnvironment();

  late Directory dir;
  setUp(() async => dir = await initTestStorage());
  tearDown(() async => dir.delete(recursive: true));

  group('sanitizeJoinLink', () {
    test('only /join/<6 alphanumerics> qualifies', () {
      expect(sanitizeJoinLink('/join/ABC123'), '/join/ABC123');
      expect(sanitizeJoinLink('/puzzle/2026-10-05'), isNull);
      expect(sanitizeJoinLink('/join/ABC12'), isNull);
      expect(sanitizeJoinLink('/groups/ABC123'), isNull);
      expect(sanitizeJoinLink('https://x.test/join/ABC123'), isNull);
      expect(sanitizeJoinLink(null), isNull);
      // Onboarding keeps its own, wider whitelist.
      expect(sanitizeDeepLink('/puzzle/2026-10-05'), '/puzzle/2026-10-05');
    });
  });

  group('PendingInvite store', () {
    test('a fresh code is returned once, then gone', () async {
      await PendingInvite.save('abc123');
      expect(await PendingInvite.consume(), 'ABC123');
      expect(await PendingInvite.consume(), isNull);
    });

    test('an expired code is ignored and cleared', () async {
      final saved = DateTime(2026, 10, 5, 12);
      await PendingInvite.save('ABC123', now: saved);
      final later = saved.add(const Duration(minutes: 31));
      expect(await PendingInvite.consume(now: later), isNull);
      expect(StorageService.pendingInviteCode, isNull);
    });

    test('a malformed stored value is ignored and cleared', () async {
      await StorageService.savePendingInvite(
        '../evil',
        DateTime.now().millisecondsSinceEpoch,
      );
      expect(await PendingInvite.consume(), isNull);
      expect(StorageService.pendingInviteCode, isNull);
    });

    test('an invalid code is never stored', () async {
      await PendingInvite.save('bad');
      expect(StorageService.pendingInviteCode, isNull);
    });
  });

  group('auth event resumes the invite', () {
    late ProviderContainer container;
    late GoRouter router;

    Future<void> start(WidgetTester tester) async {
      container = ProviderContainer(
        overrides: [authNotifierProvider.overrideWith(_FakeAuth.new)],
      );
      addTearDown(container.dispose);
      router = container.read(_routerProvider);
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
    }

    Future<void> fire(
      WidgetTester tester,
      AuthChangeEvent e, [
      User user = _member,
    ]) async {
      container
          .read(authNotifierProvider.notifier)
          .handleAuthEvent(_event(e, user));
      await tester.pumpAndSettle();
    }

    testWidgets('linked event navigates to the join route exactly once', (
      tester,
    ) async {
      await start(tester);
      await PendingInvite.save('ABC123');
      await fire(tester, AuthChangeEvent.userUpdated);
      expect(_at(router), '/join/ABC123');

      router.go('/');
      await tester.pumpAndSettle();
      await fire(tester, AuthChangeEvent.userUpdated);
      expect(_at(router), '/', reason: 'a second event must not navigate');
    });

    testWidgets('an expired code is ignored and cleared', (tester) async {
      await start(tester);
      await StorageService.savePendingInvite(
        'ABC123',
        DateTime.now()
            .subtract(const Duration(minutes: 31))
            .millisecondsSinceEpoch,
      );
      await fire(tester, AuthChangeEvent.signedIn);
      expect(_at(router), '/');
      expect(StorageService.pendingInviteCode, isNull);
    });

    testWidgets('a malformed stored value is ignored and cleared', (
      tester,
    ) async {
      await start(tester);
      await StorageService.savePendingInvite(
        'not-a-code',
        DateTime.now().millisecondsSinceEpoch,
      );
      await fire(tester, AuthChangeEvent.userUpdated);
      expect(_at(router), '/');
      expect(StorageService.pendingInviteCode, isNull);
    });

    testWidgets('a guest session event does not consume the invite', (
      tester,
    ) async {
      await start(tester);
      await PendingInvite.save('ABC123');
      await fire(tester, AuthChangeEvent.signedIn, _guest);
      expect(_at(router), '/');
      expect(StorageService.pendingInviteCode, 'ABC123');
    });
  });

  group('join screen', () {
    GoRouter joinRouter() => GoRouter(
      initialLocation: '/groups',
      routes: [
        GoRoute(path: '/groups', builder: (_, _) => const Text('GROUPS')),
        GoRoute(
          path: '/join/:code',
          builder: (_, s) =>
              JoinGroupScreen(inviteCode: s.pathParameters['code']!),
        ),
        GoRoute(path: '/auth', builder: (_, _) => const Text('AUTH')),
      ],
    );

    Future<GoRouter> pump(WidgetTester tester) async {
      final router = joinRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(
        buildTestWidgetWithRouter(
          router,
          overrides: [
            groupsSessionProvider.overrideWith(
              (ref) => const GroupsSession.signedOut(),
            ),
          ],
        ),
      );
      router.push('/join/ABC123');
      await tester.pumpAndSettle();
      return router;
    }

    testWidgets('creating an account stores the invite', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const Key('account_required_cta')));
      await tester.pumpAndSettle();
      expect(StorageService.pendingInviteCode, 'ABC123');
    });

    testWidgets('backing out of the join screen clears it', (tester) async {
      final router = await pump(tester);
      await tester.tap(find.byKey(const Key('account_required_cta')));
      await tester.pumpAndSettle();
      router.pop(); // back from /auth to the join screen
      await tester.pumpAndSettle();
      expect(StorageService.pendingInviteCode, 'ABC123');

      router.pop(); // deliberately back out of the join screen
      await tester.pumpAndSettle();
      expect(StorageService.pendingInviteCode, isNull);
    });
  });
}
