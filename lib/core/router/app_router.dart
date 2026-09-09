import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../features/auth/presentation/auth_screen.dart';
import '../../features/auth/presentation/email_auth_screen.dart';
import '../../features/auth/presentation/onboarding_screen.dart';
import '../../features/archive/presentation/archive_screen.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/groups/presentation/group_detail_screen.dart';
import '../../features/groups/presentation/groups_screen.dart';
import '../../features/groups/presentation/join_group_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/practice/presentation/practice_screen.dart';
import '../../features/practice/providers/practice_provider.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/puzzle/data/puzzle_source.dart';
import '../../features/puzzle/presentation/puzzle_screen.dart';
import '../../features/stats/presentation/stats_screen.dart';
import '../../features/profile/providers/profile_provider.dart';
import '../../shared/widgets/app_shell.dart';
import '../../shared/widgets/blocking_screens.dart';
import '../services/app_config_provider.dart';
import '../services/app_config_service.dart';
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
      final path = state.uri.path;
      final gate = ref.read(appGateProvider);
      if (gate == AppGate.maintenance && path != '/maintenance') {
        return '/maintenance';
      }
      if (gate == AppGate.forceUpdate && path != '/force-update') {
        return '/force-update';
      }
      if (gate == AppGate.ok &&
          (path == '/maintenance' || path == '/force-update')) {
        return '/';
      }
      final banned = ref.read(isBannedProvider);
      if (banned && path != '/banned') {
        return '/banned';
      }
      if (!banned && path == '/banned') {
        return '/';
      }
      // Onboarding only applies once no blocking gate is active.
      if (!StorageService.hasSeenOnboarding && path != '/onboarding') {
        return '/onboarding';
      }
      return null;
    },
    refreshListenable: _RouterRefresh(ref),
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
          return PuzzleScreen(source: PuzzleSource.forDate(date));
        },
      ),
      GoRoute(
        path: '/practice',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const PracticeScreen(),
        routes: [
          GoRoute(
            path: 'play',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) {
              final q = state.uri.queryParameters;
              final size = int.tryParse(q['size'] ?? '') ?? 5;
              final difficulty = practiceDifficulties.contains(q['difficulty'])
                  ? q['difficulty']!
                  : 'easy';
              final seed = int.tryParse(q['seed'] ?? '') ?? newPracticeSeed();
              return PuzzleScreen(
                source: PuzzleSource.practice(
                  seed: seed,
                  size: practiceSizes.contains(size) ? size : 5,
                  difficulty: difficulty,
                ),
              );
            },
          ),
        ],
      ),
      GoRoute(
        path: '/archive',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const ArchiveScreen(),
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
        builder: (context, state) => EmailAuthScreen(
          initialSignUp: state.uri.queryParameters['mode'] != 'signin',
        ),
      ),
      GoRoute(
        path: '/maintenance',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final config =
              ref.read(appConfigProvider).valueOrNull ?? AppConfig.defaults;
          return MaintenanceScreen(
            message: config.maintenanceMessage,
            onRetry: () => ref.invalidate(appConfigProvider),
          );
        },
      ),
      GoRoute(
        path: '/force-update',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final config =
              ref.read(appConfigProvider).valueOrNull ?? AppConfig.defaults;
          return ForceUpdateScreen(
            storeUrl: config.storeUrlFor(),
            latestVersion: config.latestVersion,
          );
        },
      ),
      GoRoute(
        path: '/banned',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => BannedScreen(
          onSignOut: () => ref.read(authNotifierProvider.notifier).signOut(),
        ),
      ),
    ],
  );
}

/// Re-evaluates router redirects when gating providers change.
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(Ref ref) {
    ref.listen<AppGate>(appGateProvider, (_, _) => notifyListeners());
    ref.listen<bool>(isBannedProvider, (_, _) => notifyListeners());
  }
}
