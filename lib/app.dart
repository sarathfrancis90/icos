import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants/app_sizes.dart';
import 'core/router/app_router.dart';
import 'core/services/app_config_provider.dart';
import 'core/services/storage_service.dart';
import 'core/services/sync_service.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';
import 'core/utils/date_utils.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/auth/providers/session_keeper.dart';
import 'features/puzzle/domain/models/puzzle.dart';
import 'features/puzzle/providers/daily_puzzle_provider.dart';
import 'features/puzzle/providers/puzzle_result_provider.dart';
import 'features/stats/providers/stats_provider.dart';

class IcosApp extends ConsumerStatefulWidget {
  const IcosApp({super.key});

  @override
  ConsumerState<IcosApp> createState() => _IcosAppState();
}

class _IcosAppState extends ConsumerState<IcosApp>
    with WidgetsBindingObserver {
  String _lastKnownDate = AppDateUtils.todayUtc();
  String? _lastUserId = StorageService.activeUserId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onAppStart());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onAppStart() {
    // Instantiate the sync queue so queued results flush on launch.
    ref.read(syncNotifierProvider);
    // Re-creates the guest session on reconnect / when it is lost.
    ref.read(sessionKeeperProvider);
    ref.read(puzzleRepositoryProvider).preCacheTomorrowPuzzle();

    // Local records are per user: when the signed-in user changes, everything
    // derived from them is stale (main() has already switched the storage
    // scope by the time this fires).
    ref.listenManual(authStateChangesProvider, (prev, next) {
      final id = next.valueOrNull?.session?.user.id;
      if (id == _lastUserId) return;
      _lastUserId = id;
      ref.read(submissionResultsVersionProvider.notifier).bump();
      ref.invalidate(statsOverviewProvider);
      ref.invalidate(solveHistoryProvider);
      ref.invalidate(streakProvider);
      ref.read(syncNotifierProvider.notifier).flush();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    ref.invalidate(appConfigProvider);
    ref.read(sessionKeeperProvider.notifier).ensure();
    ref.read(puzzleRepositoryProvider).preCacheTomorrowPuzzle();
    ref.read(syncNotifierProvider.notifier).flush();

    // Today's puzzle is still the offline stand-in (server was unreachable
    // earlier): try for the real one again.
    final todayDate = AppDateUtils.todayUtc();
    if (ref.read(dailyPuzzleProvider).valueOrNull?.origin ==
        PuzzleOrigin.bundled) {
      ref.invalidate(puzzleForDateProvider(todayDate));
    }

    // Crossed midnight UTC while backgrounded: today's puzzle changed.
    final today = AppDateUtils.todayUtc();
    if (today != _lastKnownDate) {
      _lastKnownDate = today;
      ref.invalidate(dailyPuzzleProvider);
      ref.invalidate(todayResultProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeNotifierProvider);

    return MaterialApp.router(
      title: 'Icos',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      themeAnimationDuration:
          const Duration(milliseconds: AppSizes.themeTransitionMs),
      routerConfig: router,
    );
  }
}
