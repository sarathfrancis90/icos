import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants/app_sizes.dart';
import 'core/router/app_router.dart';
import 'core/services/app_config_provider.dart';
import 'core/services/sync_service.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';
import 'core/utils/date_utils.dart';
import 'features/puzzle/providers/daily_puzzle_provider.dart';
import 'features/puzzle/providers/puzzle_result_provider.dart';

class IcosApp extends ConsumerStatefulWidget {
  const IcosApp({super.key});

  @override
  ConsumerState<IcosApp> createState() => _IcosAppState();
}

class _IcosAppState extends ConsumerState<IcosApp>
    with WidgetsBindingObserver {
  String _lastKnownDate = AppDateUtils.todayUtc();

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
    ref.read(puzzleRepositoryProvider).preCacheTomorrowPuzzle();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    ref.invalidate(appConfigProvider);
    ref.read(puzzleRepositoryProvider).preCacheTomorrowPuzzle();
    ref.read(syncNotifierProvider.notifier).flush();

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
