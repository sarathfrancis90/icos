import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:icos/features/auth/domain/auth_outcome.dart';
import 'package:icos/features/auth/presentation/auth_screen.dart';
import 'package:icos/features/auth/presentation/widgets/auth_outcome_handler.dart';
import 'package:icos/features/auth/providers/auth_provider.dart';
import 'package:icos/features/groups/presentation/join_group_screen.dart';
import 'package:icos/features/groups/providers/groups_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import '../../helpers/test_helpers.dart';

class _FakeAuth extends AuthNotifier {
  @override
  AsyncValue<User?> build() => const AsyncValue.data(null);
}

const _user = User(
  id: 'u',
  appMetadata: {},
  userMetadata: {},
  aud: 'authenticated',
  createdAt: '2026-10-05T00:00:00Z',
);

String _at(GoRouter r) =>
    r.routerDelegate.currentConfiguration.last.matchedLocation;

void main() {
  setUpTestEnvironment();

  group('pending join survives account creation', () {
    testWidgets('the join screen sends the invite along to /auth', (
      tester,
    ) async {
      final visited = <String>[];
      final router = GoRouter(
        initialLocation: '/join/ABC123',
        routes: [
          GoRoute(
            path: '/join/:code',
            builder: (_, s) =>
                JoinGroupScreen(inviteCode: s.pathParameters['code']!),
          ),
          GoRoute(
            path: '/auth',
            builder: (_, s) {
              visited.add(s.uri.toString());
              return const Scaffold(body: Text('auth'));
            },
          ),
          GoRoute(path: '/groups', builder: (_, _) => const Text('groups')),
        ],
      );
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
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('account_required_cta')));
      await tester.pumpAndSettle();

      final uri = Uri.parse(visited.single);
      expect(uri.path, '/auth');
      expect(uri.queryParameters['from'], '/join/ABC123');
    });

    GoRouter authRouter(String? from, List<String> emailVisits) => GoRouter(
      initialLocation: '/auth',
      routes: [
        GoRoute(
          path: '/auth',
          builder: (_, _) => AuthScreen(nextLocation: from),
        ),
        GoRoute(
          path: '/auth/email',
          builder: (_, s) {
            emailVisits.add(s.uri.toString());
            return const Scaffold(body: Text('email form'));
          },
        ),
        GoRoute(path: '/', builder: (_, _) => const Text('HOME')),
        GoRoute(path: '/join/:code', builder: (_, _) => const Text('JOIN')),
      ],
    );

    Widget app(GoRouter router) => buildTestWidgetWithRouter(
      router,
      overrides: [
        authNotifierProvider.overrideWith(_FakeAuth.new),
        isGuestProvider.overrideWithValue(true),
      ],
    );

    testWidgets('the email form keeps the pending join', (tester) async {
      final visits = <String>[];
      final router = authRouter('/join/ABC123', visits);
      addTearDown(router.dispose);
      await tester.pumpWidget(app(router));
      await tester.pump();
      await tester.tap(find.textContaining('Already have an account?'));
      await tester.pumpAndSettle();

      expect(Uri.parse(visits.single).queryParameters['from'], '/join/ABC123');
      expect(visits.single, contains('mode=signin'));
    });

    testWidgets('only /join/<6 alphanumerics> is carried', (tester) async {
      final visits = <String>[];
      final router = authRouter('https://evil.example/join/ABC123', visits);
      addTearDown(router.dispose);
      await tester.pumpWidget(app(router));
      await tester.pump();
      await tester.tap(find.textContaining('Already have an account?'));
      await tester.pumpAndSettle();

      expect(visits.single, isNot(contains('from=')));
    });

    Future<GoRouter> finishAuth(WidgetTester tester, String? next) async {
      final router = GoRouter(
        initialLocation: '/auth',
        routes: [
          GoRoute(
            path: '/auth',
            builder: (_, _) => Consumer(
              builder: (context, ref, _) => Scaffold(
                body: TextButton(
                  onPressed: () => handleAuthOutcome(
                    context,
                    ref,
                    const AuthSuccess(user: _user, isNewAccount: true),
                    nextLocation: next,
                  ),
                  child: const Text('finish'),
                ),
              ),
            ),
          ),
          GoRoute(path: '/', builder: (_, _) => const Text('HOME')),
          GoRoute(path: '/join/:code', builder: (_, _) => const Text('JOIN')),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(buildTestWidgetWithRouter(router));
      await tester.tap(find.text('finish'));
      await tester.pumpAndSettle();
      return router;
    }

    testWidgets('a created account lands on the join flow', (tester) async {
      final router = await finishAuth(tester, '/join/ABC123');
      expect(_at(router), '/join/ABC123');
    });

    testWidgets('without a pending join (or with a bad one) it lands on Home', (
      tester,
    ) async {
      expect(_at(await finishAuth(tester, null)), '/');
      expect(_at(await finishAuth(tester, '/groups/steal')), '/');
    });
  });
}
