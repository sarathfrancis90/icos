import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:icos/core/constants/app_strings.dart';
import 'package:icos/features/auth/presentation/auth_screen.dart';
import 'package:icos/features/auth/providers/auth_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import '../../../helpers/test_helpers.dart';

/// The screen reads auth state on build, which would otherwise reach for an
/// uninitialised Supabase instance.
class _FakeAuth extends AuthNotifier {
  @override
  AsyncValue<User?> build() => const AsyncValue.data(null);
}

void main() {
  group('AuthScreen', () {
    /// Routes far enough to assert where a tap sends the user, without
    /// dragging the real email screen (and Supabase) into the test.
    Widget build({List<String>? visited}) {
      final router = GoRouter(
        initialLocation: '/auth',
        routes: [
          GoRoute(
            path: '/auth',
            builder: (_, _) => const AuthScreen(),
          ),
          GoRoute(
            path: '/auth/email',
            builder: (context, state) {
              visited?.add(state.uri.toString());
              return const Scaffold(body: Text('email form'));
            },
          ),
          GoRoute(path: '/', builder: (_, _) => const Scaffold()),
        ],
      );
      return buildTestWidgetWithRouter(
        router,
        overrides: [
          authNotifierProvider.overrideWith(_FakeAuth.new),
          isGuestProvider.overrideWithValue(true),
        ],
      );
    }

    testWidgets('offers a way in for someone who already has an account',
        (tester) async {
      await tester.pumpWidget(build());
      await tester.pump();

      expect(
        find.textContaining('Already have an account?'),
        findsOneWidget,
        reason: 'returning players had no route in at all',
      );
    });

    testWidgets('the sign-in link opens the form in sign-in mode',
        (tester) async {
      final visited = <String>[];
      await tester.pumpWidget(build(visited: visited));
      await tester.pump();

      await tester.tap(find.textContaining('Already have an account?'));
      await tester.pumpAndSettle();

      expect(visited, isNotEmpty);
      expect(
        visited.single,
        contains('mode=signin'),
        reason: 'without mode=signin the email form opens on Create Account',
      );
    });

    testWidgets('the email button is labelled as sign-up, not ambiguous',
        (tester) async {
      await tester.pumpWidget(build());
      await tester.pump();

      expect(find.text(AppStrings.signUpWithEmail), findsOneWidget);
    });

    testWidgets('shows the Terms/Privacy consent line with both links',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(build());
      await tester.pump();

      expect(find.textContaining('By continuing, you agree to our'),
          findsOneWidget);
      expect(find.bySemanticsLabel('Terms of Service'), findsOneWidget);
      expect(find.bySemanticsLabel('Privacy Policy'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('does not overflow at 200% text on 320x568', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 568),
            textScaler: TextScaler.linear(2),
          ),
          child: build(),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('both providers are offered', (tester) async {
      await tester.pumpWidget(build());
      await tester.pump();

      expect(find.text(AppStrings.signInWithGoogle), findsWidgets);
    });
  });
}
