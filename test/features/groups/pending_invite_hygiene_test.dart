import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:icos/core/router/invite_continuation.dart';
import 'package:icos/core/router/pending_invite_sweeper.dart';
import 'package:icos/core/services/storage_service.dart';
import 'package:icos/core/utils/app_error.dart';
import 'package:icos/core/utils/result.dart';
import 'package:icos/features/auth/presentation/widgets/auth_outcome_handler.dart';
import 'package:icos/features/auth/domain/auth_outcome.dart';
import 'package:icos/features/auth/providers/auth_provider.dart';
import 'package:icos/features/groups/domain/models/group.dart';
import 'package:icos/features/groups/domain/pending_invite.dart';
import 'package:icos/features/groups/presentation/join_group_screen.dart';
import 'package:icos/features/groups/providers/groups_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthChangeEvent, AuthState, Session, User;

import '../../helpers/storage_test_helpers.dart';
import '../../helpers/test_helpers.dart';

final _group = Group(
  id: 'g-1',
  name: 'Sunday Solvers',
  description: '',
  inviteCode: 'ABC123',
  adminId: 'u-1',
  memberCount: 2,
  maxMembers: 50,
  isActive: true,
  createdAt: DateTime.utc(2026, 9, 1),
);

class _FakeAuth extends AuthNotifier {
  @override
  AsyncValue<User?> build() => const AsyncValue.data(null);
}

class _RecordingGroups extends MyGroups {
  static final joined = <String>[];

  @override
  Future<List<Group>> build() async => const [];

  @override
  Future<Result<Group, AppError>> joinGroup(String inviteCode) async {
    joined.add(inviteCode);
    return Result.success(_group);
  }
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

  late Directory dir;
  setUp(() async {
    dir = await initTestStorage();
    _RecordingGroups.joined.clear();
  });
  tearDown(() async => dir.delete(recursive: true));

  group('PendingInvite.clearUnlessActive', () {
    Future<bool> kept(String location, {String code = 'ABC123'}) async {
      await PendingInvite.save(code);
      await PendingInvite.clearUnlessActive(Uri.parse(location));
      return StorageService.pendingInviteCode != null;
    }

    test('stays on the join screen for that code (any case)', () async {
      expect(await kept('/join/ABC123'), isTrue);
      expect(await kept('/join/abc123'), isTrue);
    });

    test('stays on an auth screen opened from that join screen', () async {
      expect(await kept('/auth?from=/join/ABC123'), isTrue);
      expect(await kept('/auth?from=%2Fjoin%2Fabc123'), isTrue);
      expect(await kept('/auth/email?from=/join/ABC123&mode=signin'), isTrue);
    });

    test('is dropped everywhere else', () async {
      expect(await kept('/'), isFalse);
      expect(await kept('/groups'), isFalse);
      expect(await kept('/puzzle/2026-10-05'), isFalse);
      expect(await kept('/join/ZZZ999'), isFalse, reason: 'another invite');
      expect(await kept('/auth'), isFalse, reason: 'auth not from the invite');
      expect(await kept('/auth?from=/join/ZZZ999'), isFalse);
      expect(await kept('/auth?from=/'), isFalse);
      expect(await kept('/authentic?from=/join/ABC123'), isFalse);
    });

    test('with nothing stored it does nothing', () async {
      await PendingInvite.clearUnlessActive(Uri.parse('/'));
      expect(StorageService.pendingInviteCode, isNull);
    });
  });

  group('the sweeper (app start and resume)', () {
    late GoRouter router;

    Future<void> start(WidgetTester tester, String initial) async {
      router = GoRouter(
        initialLocation: initial,
        routes: [
          GoRoute(path: '/', builder: (_, _) => const Text('HOME')),
          GoRoute(path: '/groups', builder: (_, _) => const Text('GROUPS')),
          GoRoute(path: '/join/:code', builder: (_, _) => const Text('JOIN')),
          GoRoute(path: '/auth', builder: (_, _) => const Text('AUTH')),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: router,
          builder: (context, child) =>
              PendingInviteSweeper(router: router, child: child!),
        ),
      );
      await tester.pumpAndSettle();
    }

    void resume(WidgetTester tester) {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    }

    testWidgets('an invite older than 10 minutes is cleared on app start', (
      tester,
    ) async {
      await PendingInvite.save(
        'ABC123',
        now: DateTime.now().subtract(const Duration(minutes: 11)),
      );
      await start(tester, '/');
      expect(StorageService.pendingInviteCode, isNull);
    });

    testWidgets('a younger invite survives a cold start on any route (the '
        'auth callback may be what started the app)', (tester) async {
      await PendingInvite.save(
        'ABC123',
        now: DateTime.now().subtract(const Duration(minutes: 1)),
      );
      await start(tester, '/');
      expect(StorageService.pendingInviteCode, 'ABC123');
    });

    testWidgets('a cold start straight into that join link keeps it', (
      tester,
    ) async {
      await PendingInvite.save('ABC123');
      await start(tester, '/join/ABC123');
      expect(StorageService.pendingInviteCode, 'ABC123');
    });

    testWidgets('resume keeps it on the join screen and on auth opened from '
        'it, and drops it after navigating away with go()', (tester) async {
      await start(tester, '/join/ABC123');
      await PendingInvite.save('ABC123'); // saved by "Create account"

      resume(tester);
      await tester.pumpAndSettle();
      expect(StorageService.pendingInviteCode, 'ABC123');

      router.push('/auth?from=/join/ABC123');
      await tester.pumpAndSettle();
      expect(_at(router), '/auth');
      resume(tester); // back from the browser mid-OAuth
      await tester.pumpAndSettle();
      expect(StorageService.pendingInviteCode, 'ABC123');

      router.go('/groups');
      await tester.pumpAndSettle();
      resume(tester);
      await tester.pumpAndSettle();
      expect(StorageService.pendingInviteCode, isNull);
    });
  });

  group('the join screen reached by a resumed invite', () {
    Future<GoRouter> open(WidgetTester tester, {required String via}) async {
      final router = GoRouter(
        initialLocation: '/groups',
        routes: [
          GoRoute(path: '/groups', builder: (_, _) => const Text('GROUPS')),
          GoRoute(path: '/groups/:id', builder: (_, _) => const Text('GROUP')),
          GoRoute(
            path: '/join/:code',
            builder: (_, s) => JoinGroupScreen(
              inviteCode: s.pathParameters['code']!,
              autoJoin: s.extra != JoinEntry.resumedInvite,
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        buildTestWidgetWithRouter(
          router,
          overrides: [
            groupsSessionProvider.overrideWith(
              (ref) => const GroupsSession(userId: 'u', isAnonymous: false),
            ),
            myGroupsProvider.overrideWith(_RecordingGroups.new),
          ],
        ),
      );
      await tester.pumpAndSettle();
      if (via == 'resumed') {
        router.go('/join/ABC123', extra: JoinEntry.resumedInvite);
      } else {
        router.go('/join/ABC123');
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      return router;
    }

    testWidgets('does not join by itself: shows the invite and a button', (
      tester,
    ) async {
      await open(tester, via: 'resumed');
      await tester.pump(const Duration(seconds: 2));

      expect(_RecordingGroups.joined, isEmpty);
      expect(find.text('Join this group?'), findsOneWidget);
      expect(find.text('Invite code ABC123'), findsOneWidget);
      expect(find.byKey(const Key('join_confirm')), findsOneWidget);
      expect(find.text('Join group'), findsOneWidget);
    });

    testWidgets('joins when the button is tapped', (tester) async {
      await open(tester, via: 'resumed');
      await tester.tap(find.byKey(const Key('join_confirm')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2)); // the "You're in" beat
      await tester.pumpAndSettle();
      expect(_RecordingGroups.joined, ['ABC123']);
    });

    testWidgets('"Not now" leaves without joining', (tester) async {
      final router = await open(tester, via: 'resumed');
      await tester.tap(find.byKey(const Key('join_decline')));
      await tester.pumpAndSettle();
      expect(_RecordingGroups.joined, isEmpty);
      expect(_at(router), '/groups');
    });

    testWidgets('a fresh link tap still joins at once', (tester) async {
      await open(tester, via: 'link');
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(_RecordingGroups.joined, ['ABC123']);
      expect(find.byKey(const Key('join_confirm')), findsNothing);
    });
  });

  group('who sets the resumed flag', () {
    testWidgets('the continuation after sign-in asks, it does not auto-join', (
      tester,
    ) async {
      final extras = <Object?>[];
      late ProviderContainer container;
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, _) => const SizedBox()),
          GoRoute(
            path: '/join/:code',
            builder: (_, s) {
              extras.add(s.extra);
              return const SizedBox();
            },
          ),
        ],
      );
      final provider = Provider<GoRouter>((ref) {
        wireInviteContinuation(ref, router);
        return router;
      });
      container = ProviderContainer();
      addTearDown(container.dispose);
      addTearDown(router.dispose);
      container.read(provider);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      container.read(inviteContinuationProvider.notifier).offer('ABC123');
      await tester.pumpAndSettle();
      expect(extras, [JoinEntry.resumedInvite]);
    });

    testWidgets('finishing sign-in with a stored invite resumes it; with an '
        'in-visit "from" it does not mark it resumed', (tester) async {
      Future<Object?> finish(String? next, {required bool stored}) async {
        if (stored) await PendingInvite.save('ABC123');
        Object? extra = 'unset';
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
            GoRoute(
              path: '/join/:code',
              builder: (_, s) {
                extra = s.extra;
                return const Text('JOIN');
              },
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(buildTestWidgetWithRouter(router));
        await tester.tap(find.text('finish'));
        await tester.pumpAndSettle();
        return extra;
      }

      expect(await finish(null, stored: true), JoinEntry.resumedInvite);
      expect(await finish('/join/ABC123', stored: false), isNull);
      expect(
        await finish('/join/ABC123', stored: true),
        isNull,
        reason: 'back from sign-up within the same visit: join at once',
      );
    });
  });

  group('a cold start from the auth callback', () {
    final linked = AuthState(
      AuthChangeEvent.userUpdated,
      Session(accessToken: 't', tokenType: 'bearer', user: _user),
    );

    GoRouter newRouter(List<Object?> extras) => GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const SizedBox()),
        GoRoute(
          path: '/join/:code',
          builder: (_, s) {
            extras.add(s.extra);
            return const SizedBox();
          },
        ),
      ],
    );

    testWidgets('a 1-minute-old invite is kept at start, and the linked event '
        'then goes to the join confirmation once', (tester) async {
      await PendingInvite.save(
        'ABC123',
        now: DateTime.now().subtract(const Duration(minutes: 1)),
      );
      final extras = <Object?>[];
      final router = newRouter(extras);
      addTearDown(router.dispose);
      final container = ProviderContainer(
        overrides: [authNotifierProvider.overrideWith(_FakeAuth.new)],
      );
      addTearDown(container.dispose);
      container.read(
        Provider<GoRouter>((ref) {
          wireInviteContinuation(ref, router);
          return router;
        }),
      );
      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: router,
          builder: (_, child) =>
              PendingInviteSweeper(router: router, child: child!),
        ),
      );
      await tester.pumpAndSettle();
      expect(StorageService.pendingInviteCode, 'ABC123');

      container.read(authNotifierProvider.notifier).handleAuthEvent(linked);
      await tester.pumpAndSettle();
      expect(_at(router), '/join/ABC123');
      expect(extras, [JoinEntry.resumedInvite]);
      expect(StorageService.pendingInviteCode, isNull);

      container.read(authNotifierProvider.notifier).handleAuthEvent(linked);
      await tester.pumpAndSettle();
      expect(extras, hasLength(1), reason: 'consumed exactly once');
    });

    testWidgets('a linked event that arrives before the router exists still '
        'navigates once it does', (tester) async {
      await PendingInvite.save('ABC123');
      final container = ProviderContainer(
        overrides: [authNotifierProvider.overrideWith(_FakeAuth.new)],
      );
      addTearDown(container.dispose);
      container.read(authNotifierProvider.notifier).handleAuthEvent(linked);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(container.read(inviteContinuationProvider), 'ABC123');

      final extras = <Object?>[];
      final router = newRouter(extras);
      addTearDown(router.dispose);
      container.read(
        Provider<GoRouter>((ref) {
          wireInviteContinuation(ref, router);
          return router;
        }),
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      expect(_at(router), '/join/ABC123');
      expect(extras, [JoinEntry.resumedInvite]);
      expect(container.read(inviteContinuationProvider), isNull);
    });
  });
}
