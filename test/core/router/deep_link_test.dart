import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:icos/core/router/deep_link.dart';
import 'package:icos/core/services/storage_service.dart';
import 'package:icos/features/auth/presentation/onboarding_screen.dart';

import '../../helpers/storage_test_helpers.dart';
import '../../helpers/test_helpers.dart';

void main() {
  setUpTestEnvironment();

  group('sanitizeDeepLink', () {
    test('accepts join and puzzle links only', () {
      expect(sanitizeDeepLink('/join/ABC123'), '/join/ABC123');
      expect(sanitizeDeepLink('/puzzle/2026-10-05'), '/puzzle/2026-10-05');
    });

    test('rejects malformed or unknown locations', () {
      for (final bad in [
        null,
        '',
        '/join/ABC',
        '/join/ABC1234',
        '/join/AB-123',
        '/puzzle/today',
        '/profile',
        'https://evil.test/join/ABC123',
        '//evil.test/join/ABC123',
      ]) {
        expect(sanitizeDeepLink(bad), isNull, reason: '$bad');
      }
    });
  });

  group('onboardingRedirect', () {
    test('keeps the requested invite link for first-time users', () {
      final loc = onboardingRedirect(
        uri: Uri.parse('/join/ABC123'),
        hasSeenOnboarding: false,
      );
      expect(Uri.parse(loc!).path, '/onboarding');
      expect(Uri.parse(loc).queryParameters['from'], '/join/ABC123');
    });

    test('plain onboarding for ordinary locations; none once seen', () {
      expect(
        onboardingRedirect(uri: Uri.parse('/stats'), hasSeenOnboarding: false),
        '/onboarding',
      );
      expect(
        onboardingRedirect(
          uri: Uri.parse('/join/ABC123'),
          hasSeenOnboarding: true,
        ),
        isNull,
      );
    });
  });

  group('onboarding flow', () {
    Future<void> pumpFlow(WidgetTester tester, String initial) async {
      final router = GoRouter(
        initialLocation: initial,
        redirect: (context, state) => onboardingRedirect(
          uri: state.uri,
          hasSeenOnboarding: StorageService.hasSeenOnboarding,
        ),
        routes: [
          GoRoute(
            path: '/onboarding',
            builder: (_, state) => OnboardingScreen(
              nextLocation: sanitizeDeepLink(state.uri.queryParameters['from']),
            ),
          ),
          GoRoute(path: '/', builder: (_, _) => const Text('HOME')),
          GoRoute(
            path: '/join/:code',
            builder: (_, s) => Text('JOIN ${s.pathParameters['code']}'),
          ),
        ],
      );
      await tester.pumpWidget(buildTestWidgetWithRouter(router));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
    }

    testWidgets(
      'fresh install opening /join/ABC123 lands on that join screen',
      (tester) async {
        await tester.runAsync(() => initTestStorage());
        await pumpFlow(tester, '/join/ABC123');
        expect(find.text('JOIN ABC123'), findsOneWidget);
      },
    );

    testWidgets('malformed pending location falls back to Home', (
      tester,
    ) async {
      await tester.runAsync(() => initTestStorage());
      await pumpFlow(tester, '/onboarding?from=%2Fprofile');
      expect(find.text('HOME'), findsOneWidget);
    });
  });
}
