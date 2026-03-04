import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../features/auth/presentation/auth_screen.dart';
import '../../features/auth/presentation/email_auth_screen.dart';
import '../../features/auth/presentation/onboarding_screen.dart';
import '../../features/groups/presentation/group_detail_screen.dart';
import '../../features/groups/presentation/groups_screen.dart';
import '../../features/groups/presentation/join_group_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/puzzle/presentation/puzzle_screen.dart';
import '../../features/stats/presentation/stats_screen.dart';
import '../../shared/widgets/app_shell.dart';
import '../services/storage_service.dart';

part 'app_router.g.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

@riverpod
GoRouter appRouter(Ref ref) {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/',
    redirect: (context, state) {
      if (!StorageService.hasSeenOnboarding &&
          state.uri.path != '/onboarding') {
        return '/onboarding';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/onboarding',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const OnboardingScreen(),
      ),
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: HomeScreen(),
            ),
          ),
          GoRoute(
            path: '/groups',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: GroupsScreen(),
            ),
          ),
          GoRoute(
            path: '/stats',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: StatsScreen(),
            ),
          ),
          GoRoute(
            path: '/profile',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ProfileScreen(),
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/puzzle/:date',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final date = state.pathParameters['date']!;
          return PuzzleScreen(date: date);
        },
      ),
      GoRoute(
        path: '/groups/:id',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final groupId = state.pathParameters['id']!;
          return GroupDetailScreen(groupId: groupId);
        },
      ),
      GoRoute(
        path: '/join/:code',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final code = state.pathParameters['code']!;
          return JoinGroupScreen(inviteCode: code);
        },
      ),
      GoRoute(
        path: '/auth',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const AuthScreen(),
      ),
      GoRoute(
        path: '/auth/email',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const EmailAuthScreen(),
      ),
    ],
  );
}
