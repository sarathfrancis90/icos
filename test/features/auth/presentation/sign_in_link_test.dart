import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:icos/core/services/storage_service.dart';
import 'package:icos/features/auth/presentation/email_auth_screen.dart';
import 'package:icos/features/auth/providers/auth_provider.dart';
import 'package:icos/features/groups/presentation/join_group_screen.dart';
import 'package:icos/features/groups/presentation/widgets/account_required_card.dart';
import 'package:icos/features/groups/providers/groups_provider.dart';
import 'package:icos/features/profile/presentation/widgets/guest_account_card.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import '../../../helpers/storage_test_helpers.dart';
import '../../../helpers/test_helpers.dart';

class _FakeAuth extends AuthNotifier {
  @override
  AsyncValue<User?> build() => const AsyncValue.data(null);
}

const _signInLabel = 'Sign in to an existing account';

GoRouter _router(Widget home) => GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (_, _) => Scaffold(body: home),
    ),
    GoRoute(
      path: '/auth',
      builder: (_, _) => const Scaffold(body: Text('AUTH_HOME')),
    ),
    GoRoute(
      path: '/auth/email',
      builder: (_, s) => EmailAuthScreen(
        initialSignUp: s.uri.queryParameters['mode'] != 'signin',
        nextLocation: s.uri.queryParameters['from'],
      ),
    ),
    GoRoute(
      path: '/join/:code',
      builder: (_, s) => JoinGroupScreen(inviteCode: s.pathParameters['code']!),
    ),
  ],
);

Future<GoRouter> _pump(
  WidgetTester tester,
  Widget home, {
  String initial = '/',
  double scale = 1,
}) async {
  final router = _router(home);
  addTearDown(router.dispose);
  if (initial != '/') router.go(initial);
  tester.view.physicalSize = const Size(320, 568);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authNotifierProvider.overrideWith(_FakeAuth.new),
        isGuestProvider.overrideWithValue(true),
        groupsSessionProvider.overrideWith(
          (ref) => const GroupsSession(userId: 'a', isAnonymous: true),
        ),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void _expectSignInMode(WidgetTester tester) {
  expect(find.byType(EmailAuthScreen), findsOneWidget);
  expect(find.text('Welcome Back'), findsOneWidget);
  expect(find.text('Sign In'), findsWidgets);
  expect(find.text('Confirm Password'), findsNothing);
}

void main() {
  setUpTestEnvironment();

  late Directory dir;
  setUp(() async => dir = await initTestStorage());
  tearDown(() => dir.delete(recursive: true));

  for (final entry in {
    'profile guest card': (const GuestAccountCard(), <String, Object>{}),
    'groups account card': (const AccountRequiredCard(), <String, Object>{}),
  }.entries) {
    group(entry.key, () {
      testWidgets('shows both actions with semantics', (tester) async {
        final handle = tester.ensureSemantics();
        await _pump(tester, entry.value.$1);
        expect(find.byKey(const Key('sign_in_link')), findsOneWidget);
        expect(find.text('Sign in'), findsOneWidget);
        expect(find.bySemanticsLabel(_signInLabel), findsOneWidget);
        expect(
          tester.getSize(find.byKey(const Key('sign_in_link'))).height,
          greaterThanOrEqualTo(44),
        );
        handle.dispose();
      });

      testWidgets('Sign in opens the email form in sign-in mode', (
        tester,
      ) async {
        await _pump(tester, entry.value.$1);
        await tester.ensureVisible(find.byKey(const Key('sign_in_link')));
        await tester.tap(find.byKey(const Key('sign_in_link')));
        await tester.pumpAndSettle();
        _expectSignInMode(tester);
      });

      testWidgets('no overflow at 200% on 320x568', (tester) async {
        await _pump(
          tester,
          SingleChildScrollView(child: entry.value.$1),
          scale: 2,
        );
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('sign_in_link')), findsOneWidget);
      });
    });
  }

  testWidgets('Create account on the profile card still opens /auth', (
    tester,
  ) async {
    await _pump(tester, const GuestAccountCard());
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    expect(find.text('AUTH_HOME'), findsOneWidget);
  });

  group('join screen invite continuation', () {
    testWidgets(
      'Create account is unchanged: saves the invite, goes to /auth',
      (tester) async {
        final router = await _pump(
          tester,
          const SizedBox(),
          initial: '/join/ABC123',
        );
        await tester.tap(find.byKey(const Key('account_required_cta')));
        await tester.pumpAndSettle();
        expect(find.text('AUTH_HOME'), findsOneWidget);
        expect(
          GoRouterState.of(
            tester.element(find.byType(Scaffold).last),
          ).uri.toString(),
          '/auth?from=%2Fjoin%2FABC123',
        );
        expect(StorageService.pendingInviteCode, 'ABC123');
      },
    );

    testWidgets('Sign in keeps the invite and opens sign-in mode', (
      tester,
    ) async {
      final router = await _pump(
        tester,
        const SizedBox(),
        initial: '/join/ABC123',
      );
      await tester.tap(find.byKey(const Key('sign_in_link')));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      _expectSignInMode(tester);
      final uri = GoRouterState.of(
        tester.element(find.byType(Scaffold).last),
      ).uri;
      expect(uri.path, '/auth/email');
      expect(uri.queryParameters, {'mode': 'signin', 'from': '/join/ABC123'});
      expect(StorageService.pendingInviteCode, 'ABC123');
    });
  });
}
