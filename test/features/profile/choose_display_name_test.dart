import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:icos/core/constants/app_strings.dart';
import 'package:icos/core/services/auth_session_provider.dart';
import 'package:icos/core/services/storage_service.dart';
import 'package:icos/core/utils/app_error.dart';
import 'package:icos/core/utils/result.dart';
import 'package:icos/features/auth/domain/auth_outcome.dart';
import 'package:icos/features/auth/presentation/widgets/auth_outcome_handler.dart';
import 'package:icos/features/groups/domain/pending_invite.dart';
import 'package:icos/features/profile/data/profile_repository.dart';
import 'package:icos/features/profile/domain/display_name_placeholder.dart';
import 'package:icos/features/profile/domain/models/profile.dart';
import 'package:icos/features/profile/presentation/widgets/choose_display_name_sheet.dart';
import 'package:icos/features/profile/providers/profile_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import '../../helpers/storage_test_helpers.dart';
import '../../helpers/test_helpers.dart';

class _Repo extends ProfileRepository {
  _Repo(this.name);
  String name;
  bool failGet = false;
  int gets = 0;
  final saved = <String>[];

  UserProfile _p(String id) =>
      UserProfile(id: id, displayName: name, isAnonymous: false);

  @override
  Future<Result<UserProfile, AppError>> getProfile(String userId) async {
    gets++;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    if (failGet) return Result.failure(AppError.network('offline'));
    return Result.success(_p(userId));
  }

  @override
  Future<Result<UserProfile, AppError>> updateProfile(
    String userId, {
    String? displayName,
    String? avatarUrl,
    String? colorblindMode,
  }) async {
    saved.add(displayName!);
    name = displayName;
    return Result.success(_p(userId));
  }
}

User _user({Map<String, dynamic> meta = const {}, String? email}) => User(
  id: 'u1',
  email: email,
  appMetadata: const {},
  userMetadata: meta,
  aud: 'authenticated',
  createdAt: '2026-10-05T00:00:00Z',
);

String _at(GoRouter r) =>
    r.routerDelegate.currentConfiguration.last.matchedLocation;

void main() {
  setUpTestEnvironment();
  late Directory dir;
  setUp(() async => dir = await initTestStorage(userId: 'u1'));
  tearDown(() async => dir.delete(recursive: true));

  test('placeholder helper mirrors the database rule', () {
    expect(isPlaceholderDisplayName('Player 0042'), isTrue);
    expect(isPlaceholderDisplayName(null), isTrue);
    expect(isPlaceholderDisplayName('  '), isTrue);
    expect(isPlaceholderDisplayName('Player 42'), isFalse);
    expect(isPlaceholderDisplayName('Player 12345'), isFalse);
    expect(isPlaceholderDisplayName('Ada'), isFalse);
  });

  Future<(GoRouter, _Repo)> run(
    WidgetTester tester, {
    required String name,
    User? user,
  }) async {
    final repo = _Repo(name);
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
                  AuthSuccess(user: user ?? _user(), accountLinked: true),
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
    await tester.pumpWidget(
      buildTestWidgetWithRouter(
        router,
        overrides: [
          profileRepositoryProvider.overrideWithValue(repo),
          authSessionProvider.overrideWithValue(
            const FakeAuthSessionInfo(userId: 'u1'),
          ),
        ],
      ),
    );
    return (router, repo);
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.tap(find.text('finish'));
    await tester.pumpAndSettle();
  }

  testWidgets('shown once for a placeholder name after a link', (tester) async {
    final (router, _) = await run(tester, name: 'Player 1234');
    await finish(tester);
    expect(find.text(AppStrings.chooseNameTitle), findsOneWidget);
    expect(find.text(AppStrings.chooseNameBody), findsOneWidget);
    expect(find.text(AppStrings.chooseNameSave), findsOneWidget);
    expect(find.text(AppStrings.notNow), findsOneWidget);
    expect(StorageService.displayNamePromptShown('u1'), isTrue);

    await tester.tap(find.text(AppStrings.notNow));
    await tester.pumpAndSettle();
    expect(_at(router), '/');

    // A second sign-in for the same account does not ask again.
    router.go('/auth');
    await tester.pumpAndSettle();
    await finish(tester);
    expect(find.text(AppStrings.chooseNameTitle), findsNothing);
  });

  testWidgets('shown once even for an already chosen name, prefilled', (
    tester,
  ) async {
    final (router, _) = await run(tester, name: 'Ada Lovelace');
    await finish(tester);
    expect(find.text(AppStrings.chooseNameTitle), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Ada Lovelace'), findsOneWidget);
    expect(StorageService.displayNamePromptShown('u1'), isTrue);
    await tester.tap(find.text(AppStrings.notNow));
    await tester.pumpAndSettle();
    expect(_at(router), '/');
  });

  testWidgets('Google-style metadata prefills the provider name', (
    tester,
  ) async {
    await run(
      tester,
      name: 'Player 1234',
      user: _user(meta: {'full_name': 'Grace Hopper'}, email: 'gh@example.com'),
    );
    await finish(tester);
    expect(find.widgetWithText(TextFormField, 'Grace Hopper'), findsOneWidget);
  });

  testWidgets('plain email account prefills the tidied local part', (
    tester,
  ) async {
    await run(
      tester,
      name: 'Player 1234',
      user: _user(email: 'ada.lovelace@example.com'),
    );
    await finish(tester);
    expect(find.widgetWithText(TextFormField, 'Ada Lovelace'), findsOneWidget);
  });

  testWidgets('relay email with no name: empty field with placeholder hint', (
    tester,
  ) async {
    await run(
      tester,
      name: 'Player 1234',
      user: _user(email: 'k3x9q2@privaterelay.appleid.com'),
    );
    await finish(tester);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, isEmpty);
    expect(field.decoration!.hintText, 'Player 1234');
  });

  testWidgets('profile fetch failure: no sheet, flag stays unset, later ok', (
    tester,
  ) async {
    final (router, repo) = await run(tester, name: 'Ada Lovelace');
    repo.failGet = true;
    await finish(tester);
    expect(find.text(AppStrings.chooseNameTitle), findsNothing);
    expect(StorageService.displayNamePromptShown('u1'), isFalse);
    expect(_at(router), '/');

    repo.failGet = false;
    router.go('/auth');
    await tester.pumpAndSettle();
    await finish(tester);
    expect(find.text(AppStrings.chooseNameTitle), findsOneWidget);
  });

  testWidgets('two overlapping invocations show one sheet', (tester) async {
    final repo = _Repo('Player 1234');
    await tester.pumpWidget(
      buildTestWidgetWithRouter(
        GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => Consumer(
                builder: (context, ref, _) => TextButton(
                  onPressed: () {
                    maybePromptForDisplayName(context, ref, _user());
                    maybePromptForDisplayName(context, ref, _user());
                  },
                  child: const Text('go'),
                ),
              ),
            ),
          ],
        ),
        overrides: [profileRepositoryProvider.overrideWithValue(repo)],
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.chooseNameTitle), findsOneWidget);
    expect(repo.gets, 1);
  });

  testWidgets('Save validates, persists through the profile path', (
    tester,
  ) async {
    final (router, repo) = await run(tester, name: 'Player 1234');
    await finish(tester);
    await tester.enterText(find.byType(TextFormField), 'A');
    await tester.tap(find.text(AppStrings.chooseNameSave));
    await tester.pump();
    expect(repo.saved, isEmpty);
    expect(find.textContaining('at least'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), 'Ada Lovelace');
    await tester.tap(find.text(AppStrings.chooseNameSave));
    await tester.pumpAndSettle();
    expect(repo.saved, ['Ada Lovelace']);
    expect(_at(router), '/');
  });

  testWidgets('the pending invite continuation still happens', (tester) async {
    await PendingInvite.save('ABC123');
    final (router, _) = await run(tester, name: 'Player 1234');
    await finish(tester);
    expect(find.text(AppStrings.chooseNameTitle), findsOneWidget);
    await tester.tap(find.text(AppStrings.notNow));
    await tester.pumpAndSettle();
    expect(_at(router), '/join/ABC123');
    expect(StorageService.pendingInviteCode, isNull);
  });

  testWidgets('200% text does not overflow', (tester) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await run(tester, name: 'Player 1234');
    await finish(tester);
    expect(tester.takeException(), isNull);
    expect(find.text(AppStrings.chooseNameSave), findsOneWidget);
  });
}
