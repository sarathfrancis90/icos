import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:icos/core/constants/app_strings.dart';
import 'package:icos/core/router/app_router.dart';
import 'package:icos/core/services/app_config_provider.dart';
import 'package:icos/core/services/storage_service.dart';
import 'package:icos/features/profile/providers/profile_provider.dart';
import 'package:icos/features/auth/domain/auth_outcome.dart';
import 'package:icos/features/auth/domain/auth_strategy.dart';
import 'package:icos/features/auth/presentation/auth_screen.dart';
import 'package:icos/features/auth/providers/auth_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import '../../../helpers/storage_test_helpers.dart';
import '../../../helpers/test_helpers.dart';

class _RecordingAuth extends AuthNotifier {
  static final calls = <String>[];

  @override
  AsyncValue<User?> build() => const AsyncValue.data(null);

  @override
  Future<AuthOutcome> signInWithGoogle() async {
    calls.add('link:google');
    return const AuthCancelled();
  }

  @override
  Future<AuthOutcome> signInWithApple() async {
    calls.add('link:apple');
    return const AuthCancelled();
  }

  @override
  Future<AuthOutcome> signInToExistingWithOAuth(OAuthKind provider) async {
    calls.add('existing:${provider.name}');
    return const AuthCancelled();
  }
}

void main() {
  setUpTestEnvironment();

  late Directory dir;
  setUp(() async {
    _RecordingAuth.calls.clear();
    dir = await initTestStorage();
  });
  tearDown(() => dir.delete(recursive: true));

  Future<void> pump(WidgetTester tester, {required bool signIn}) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      buildTestWidget(
        AuthScreen(signIn: signIn),
        overrides: [
          authNotifierProvider.overrideWith(_RecordingAuth.new),
          isGuestProvider.overrideWithValue(true),
        ],
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('sign-in mode: Google uses the existing-account path, not '
      'linking, and shows the guest note', (tester) async {
    await pump(tester, signIn: true);
    expect(find.text(AppStrings.signInGuestNote), findsOneWidget);
    await tester.tap(find.text(AppStrings.signInWithGoogle));
    await tester.pumpAndSettle();
    expect(_RecordingAuth.calls, ['existing:google']);
  });

  testWidgets('sign-in mode: Apple uses the existing-account path', (
    tester,
  ) async {
    AuthNotifier.platformOverride = AuthPlatform.ios;
    addTearDown(() => AuthNotifier.platformOverride = null);
    await pump(tester, signIn: true);
    final apple = find.text(AppStrings.signInWithApple);
    expect(apple, findsOneWidget);
    await tester.tap(apple);
    await tester.pumpAndSettle();
    expect(_RecordingAuth.calls, ['existing:apple']);
  });

  testWidgets('normal mode: Apple still links the guest', (tester) async {
    AuthNotifier.platformOverride = AuthPlatform.ios;
    addTearDown(() => AuthNotifier.platformOverride = null);
    await pump(tester, signIn: false);
    final apple = find.text(AppStrings.signInWithApple);
    expect(apple, findsOneWidget);
    await tester.tap(apple);
    await tester.pumpAndSettle();
    expect(_RecordingAuth.calls, ['link:apple']);
  });

  testWidgets('normal mode: Google still links the guest, no note', (
    tester,
  ) async {
    await pump(tester, signIn: false);
    expect(find.text(AppStrings.signInGuestNote), findsNothing);
    await tester.tap(find.text(AppStrings.signInWithGoogle));
    await tester.pumpAndSettle();
    expect(_RecordingAuth.calls, ['link:google']);
  });

  testWidgets('sign-in mode offers a switch to Create account', (tester) async {
    final router = GoRouter(
      initialLocation: '/auth?mode=signin&from=/join/ABC123',
      routes: [
        GoRoute(
          path: '/auth',
          builder: (_, s) => AuthScreen(
            signIn: s.uri.queryParameters['mode'] == 'signin',
            nextLocation: s.uri.queryParameters['from'],
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      buildTestWidgetWithRouter(
        router,
        overrides: [
          authNotifierProvider.overrideWith(_RecordingAuth.new),
          isGuestProvider.overrideWithValue(true),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('auth_switch_to_create')));
    await tester.pumpAndSettle();
    final uri = router.state.uri;
    expect(uri.queryParameters['from'], '/join/ABC123');
    expect(uri.queryParameters.containsKey('mode'), isFalse);
    expect(find.text(AppStrings.welcomeBack), findsNothing);
    expect(find.text(AppStrings.signUpWithEmail), findsOneWidget);
    expect(find.text(AppStrings.signInGuestNote), findsNothing);
  });

  testWidgets('the real app router passes mode and the sanitized from to '
      'the auth screen', (tester) async {
    await StorageService.setHasSeenOnboarding(true);
    final container = ProviderContainer(
      overrides: [
        authNotifierProvider.overrideWith(_RecordingAuth.new),
        isGuestProvider.overrideWithValue(true),
        appGateProvider.overrideWithValue(AppGate.ok),
        isBannedProvider.overrideWithValue(false),
        pendingDeletionDateProvider.overrideWithValue(null),
      ],
    );
    addTearDown(container.dispose);
    final router = container.read(appRouterProvider);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    router.go('/auth?mode=signin&from=/join/ABC123');
    await tester.pumpAndSettle();
    var screen = tester.widget<AuthScreen>(find.byType(AuthScreen));
    expect(screen.signIn, isTrue);
    expect(screen.nextLocation, '/join/ABC123');

    router.go('/auth?mode=signin&from=https://evil.example/x');
    await tester.pumpAndSettle();
    screen = tester.widget<AuthScreen>(find.byType(AuthScreen));
    expect(screen.nextLocation, isNull);
  });
}
