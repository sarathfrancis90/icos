import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants/app_sizes.dart';
import 'core/router/app_router.dart';
import 'core/router/pending_invite_sweeper.dart';
import 'core/services/app_config_provider.dart';
import 'core/services/notification_service.dart';
import 'core/services/sync_service.dart';
import 'core/theme/app_palette.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';
import 'core/utils/date_utils.dart';
import 'core/utils/utc_day_rollover.dart';
import 'features/archive/providers/archive_provider.dart';
import 'features/auth/providers/session_keeper.dart';
import 'features/auth/providers/user_scope_keeper.dart';
import 'features/puzzle/domain/models/puzzle.dart';
import 'features/puzzle/providers/daily_puzzle_provider.dart';
import 'features/puzzle/providers/puzzle_result_provider.dart';
import 'features/stats/providers/stats_provider.dart';
import 'shared/widgets/text_scale_limit.dart';

class IcosApp extends ConsumerStatefulWidget {
  const IcosApp({super.key});

  @override
  ConsumerState<IcosApp> createState() => _IcosAppState();
}

class _IcosAppState extends ConsumerState<IcosApp>
    with WidgetsBindingObserver {
  // Crossing 00:00 UTC (foreground timer, or noticed on resume): today's
  // puzzle, result and streak liveness all change.
  late final UtcDayRollover _rollover = UtcDayRollover(
    onNewDay: (_) => _onNewUtcDay(),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _rollover.start();
    // A tap on the daily or streak reminder opens Home.
    NotificationService.onNotificationTap = (_) => _openHome();
    WidgetsBinding.instance.addPostFrameCallback((_) => _onAppStart());
  }

  @override
  void dispose() {
    _rollover.dispose();
    NotificationService.onNotificationTap = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _openHome() {
    if (!mounted) return;
    ref.read(appRouterProvider).go('/');
  }

  void _onNewUtcDay() {
    if (!mounted) return;
    ref.invalidate(dailyPuzzleProvider);
    ref.invalidate(todayResultProvider);
    ref.invalidate(streakProvider);
    ref.invalidate(statsOverviewProvider);
    ref.invalidate(archiveEntriesProvider);
    ref.read(puzzleRepositoryProvider).preCacheTomorrowPuzzle();
  }

  void _onAppStart() {
    // Instantiate the sync queue so queued results flush on launch.
    ref.read(syncNotifierProvider);
    // Re-creates the guest session on reconnect / when it is lost.
    ref.read(sessionKeeperProvider);
    ref.read(puzzleRepositoryProvider).preCacheTomorrowPuzzle();

    // Resets per-player state when the signed-in user id changes.
    ref.read(userScopeKeeperProvider);

    // Cold start from a notification tap.
    unawaited(NotificationService.handleLaunchFromNotification());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    ref.invalidate(appConfigProvider);
    unawaited(
      NotificationService.cancelPendingIfNotAllowed().catchError((Object _) {}),
    );
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

    // Crossed midnight UTC while backgrounded: today's puzzle changed. The
    // foreground timer may have been suspended, so re-arm it too.
    _rollover
      ..check()
      ..start();
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
      // Layouts are verified to 200% text scale; larger system sizes (iOS
      // accessibility sizes reach ~310%) are clamped rather than broken.
      // Status and navigation bar icons follow the theme (dark icons on the
      // light theme) on screens without an AppBar; AppBars set the same
      // style through the theme's AppBarTheme.
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: context.palette.overlayStyle,
        child: PendingInviteSweeper(
          router: router,
          child: TextScaleLimit(child: child ?? const SizedBox()),
        ),
      ),
    );
  }
}
