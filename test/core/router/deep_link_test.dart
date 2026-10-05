import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:icos/core/router/deep_link.dart';
import 'package:icos/core/services/app_config_provider.dart';
import 'package:icos/core/services/storage_service.dart';
import 'package:icos/features/auth/presentation/onboarding_screen.dart';

import '../../helpers/storage_test_helpers.dart';
import '../../helpers/test_helpers.dart';

void main() {
  setUpTestEnvironment();
  _appRedirectTests();

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

void _appRedirectTests() {
  group('appRedirect', () {
    const screens = {
      'maintenance': '/maintenance',
      'forceUpdate': '/force-update',
      'banned': '/banned',
      'deletion': kDeletionPendingPath,
      'recovery': kNewPasswordPath,
      'onboarding': '/onboarding',
    };
    // Priority order, highest first.
    const order = [
      'maintenance',
      'forceUpdate',
      'banned',
      'deletion',
      'recovery',
      'onboarding',
    ];

    String? redirect(Set<String> on, Uri uri) => appRedirect(
      uri: uri,
      gate: on.contains('maintenance')
          ? AppGate.maintenance
          : on.contains('forceUpdate')
          ? AppGate.forceUpdate
          : AppGate.ok,
      banned: on.contains('banned'),
      pendingDeletion: on.contains('deletion'),
      recoveryPending: on.contains('recovery'),
      hasSeenOnboarding: !on.contains('onboarding'),
    );

    String settle(Set<String> on, String start) {
      var loc = start;
      for (var i = 0; i < 5; i++) {
        final next = redirect(on, Uri.parse(loc));
        if (next == null) return loc;
        loc = next;
      }
      fail('redirect loop for $on from $start (stuck at $loc)');
    }

    test(
      'every pair of simultaneously-true gates settles on the higher one',
      () {
        for (var i = 0; i < order.length; i++) {
          for (var j = i + 1; j < order.length; j++) {
            final on = {order[i], order[j]};
            for (final start in [
              '/',
              '/stats',
              '/join/ABC123',
              ...screens.values,
            ]) {
              expect(
                Uri.parse(settle(on, start)).path,
                screens[order[i]],
                reason: '$on from $start',
              );
            }
          }
        }
      },
    );

    test('named cases and a single gate each settle on their own screen', () {
      expect(
        settle({'maintenance', 'onboarding'}, '/onboarding'),
        '/maintenance',
      );
      expect(
        settle({'forceUpdate', 'deletion'}, kDeletionPendingPath),
        '/force-update',
      );
      expect(
        settle({'maintenance', 'deletion'}, '/force-update'),
        '/maintenance',
      );
      expect(settle({'banned', 'recovery'}, kNewPasswordPath), '/banned');
      expect(
        settle({'deletion', 'recovery'}, kNewPasswordPath),
        kDeletionPendingPath,
      );
      for (final g in order) {
        expect(Uri.parse(settle({g}, '/')).path, screens[g]);
      }
      expect(settle({}, '/stats'), '/stats');
    });

    test('no gate: lingering on a blocking screen releases to home', () {
      for (final s in [
        '/maintenance',
        '/force-update',
        '/banned',
        kDeletionPendingPath,
        kNewPasswordPath,
      ]) {
        expect(settle({}, s), '/');
      }
    });
  });
}
