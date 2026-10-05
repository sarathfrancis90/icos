import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../features/archive/presentation/archive_screen.dart';
import '../../features/auth/presentation/auth_screen.dart';
import '../../features/auth/presentation/email_auth_screen.dart';
import '../../features/auth/presentation/new_password_screen.dart';
import '../../features/auth/presentation/onboarding_screen.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/groups/presentation/group_detail_screen.dart';
import '../../features/groups/presentation/groups_screen.dart';
import '../../features/groups/presentation/join_group_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/practice/presentation/practice_screen.dart';
import '../../features/practice/providers/practice_provider.dart';
import '../../features/profile/domain/account_deletion_copy.dart';
import '../../features/profile/presentation/blocked_users_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/profile/providers/profile_provider.dart';
import '../../features/puzzle/data/puzzle_source.dart';
import '../../features/puzzle/presentation/puzzle_screen.dart';
import '../../features/stats/presentation/stats_screen.dart';
import '../../shared/widgets/app_shell.dart';
import '../../shared/widgets/blocking_screens.dart';
import '../services/app_config_provider.dart';
import '../services/app_config_service.dart';
import '../services/storage_service.dart';
import '../utils/result.dart';
import 'deep_link.dart';

part 'app_router.g.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

@riverpod
GoRouter appRouter(Ref ref) {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/',
    redirect: (context, state) => appRedirect(
      uri: state.uri,
      gate: ref.read(appGateProvider),
      banned: ref.read(isBannedProvider),
      pendingDeletion: ref.read(pendingDeletionDateProvider) != null,
      recoveryPending: ref.read(passwordRecoveryPendingProvider),
      hasSeenOnboarding: StorageService.hasSeenOnboarding,
    ),
    refreshListenable: _RouterRefresh(ref),
    routes: [
      GoRoute(
        path: '/onboarding',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => OnboardingScreen(
          nextLocation: sanitizeDeepLink(state.uri.queryParameters['from']),
        ),
      ),
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: HomeScreen()),
          ),
          GoRoute(
            path: '/groups',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: GroupsScreen()),
          ),
          GoRoute(
            path: '/stats',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: StatsScreen()),
          ),
          GoRoute(
            path: '/profile',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: ProfileScreen()),
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
        path: '/blocked-users',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const BlockedUsersScreen(),
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
        builder: (context, state) => AuthScreen(
          nextLocation: sanitizeDeepLink(state.uri.queryParameters['from']),
        ),
      ),
      GoRoute(
        path: kNewPasswordPath,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const NewPasswordScreen(),
      ),
      GoRoute(
        path: '/auth/email',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => EmailAuthScreen(
          initialSignUp: state.uri.queryParameters['mode'] != 'signin',
          nextLocation: sanitizeDeepLink(state.uri.queryParameters['from']),
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
        path: kDeletionPendingPath,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final date = ref.read(pendingDeletionDateProvider) ?? DateTime.now();
          return AccountDeletionPendingScreen(
            deletionDate: date,
            onCancelDeletion: () async {
              final result = await ref
                  .read(profileNotifierProvider.notifier)
                  .cancelAccountDeletion();
              return switch (result) {
                Failure(:final error) =>
                  AccountDeletionCopy.cancelFailureMessage(error),
                _ => null,
              };
            },
            onSignOut: () => ref.read(authNotifierProvider.notifier).signOut(),
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
    ref.listen<DateTime?>(
      pendingDeletionDateProvider,
      (_, _) => notifyListeners(),
    );
    ref.listen<bool>(
      passwordRecoveryPendingProvider,
      (_, _) => notifyListeners(),
    );
  }
}
