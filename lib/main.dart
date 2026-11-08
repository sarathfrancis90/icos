import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app.dart';
import 'core/backend/auth_event.dart';
import 'core/backend/backend_providers.dart';
import 'core/services/analytics_service.dart';
import 'core/services/audio_service.dart';
import 'core/services/legacy_cleanup.dart';
import 'core/services/notification_service.dart';
import 'core/services/session_service.dart';
import 'core/services/storage_service.dart';
import 'core/theme/font_licenses.dart';
import 'features/auth/providers/auth_provider.dart' show PasswordRecoveryLatch;

Future<void> main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  // Keep semantics tree alive so accessibility tools (and Maestro E2E) can see widgets.
  // The handle must be stored to prevent garbage collection.
  // ignore: unused_local_variable
  final semanticsHandle = SemanticsBinding.instance.ensureSemantics();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // Inter ships in assets/google_fonts/: never fetch fonts from the network
  // (an undeclared third-party call that also fails offline on first launch).
  GoogleFonts.config.allowRuntimeFetching = false;
  registerFontLicenses();

  // Lock orientation to portrait on phones
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Load environment variables
  const envFile = kReleaseMode ? '.env.production' : '.env.development';
  await dotenv.load(fileName: envFile);

  // Initialize services
  await StorageService.initialize();
  await AnalyticsService.initialize();

  // Upgrade from the old backend: drop its session keys and local caches
  // before any session exists; the app then shows the fresh-start notice.
  final showFreshStartNotice = await LegacyCleanup.runIfNeeded(
    StorageService.prefs,
    clearCaches: StorageService.clearAllPlayerData,
    hasLegacyHiveData: () => StorageService.hasHiveData,
  );

  // Backend hosts first: every backend provider reads them synchronously.
  final container = ProviderContainer();
  await container.read(backendConfigProvider.future);
  final auth = container.read(authClientProvider);
  await auth.restore();

  // Per-user local data follows the signed-in user. Registered before anything
  // else listens so the scope is already switched when providers react.
  await StorageService.setActiveUser(auth.currentUser?.id);
  auth.events.listen((event) {
    if (event == AuthEvent.passwordRecovery) {
      PasswordRecoveryLatch.arrivedBeforeStart = true;
    }
    unawaited(StorageService.setActiveUser(auth.currentUser?.id));
  });

  // Guest session if there is none. Startup waits at most 5 s; the attempt
  // keeps going in the background and is retried on reconnect, on resume and
  // before the sync queue runs (see SessionKeeper). A restored session is
  // checked with the server in the background; a dead one is signed out and
  // replaced by a new guest.
  final restored = auth.currentUser != null;
  await container
      .read(sessionEnsurerProvider)
      .ensureSession()
      .timeout(const Duration(seconds: 5), onTimeout: () => false);
  if (restored) {
    unawaited(
      auth.getSession().then(
        (_) => container.read(sessionEnsurerProvider).ensureSession(),
      ),
    );
  }
  await StorageService.setActiveUser(auth.currentUser?.id);

  // Notifications (local reminders + optional FCM); never throws.
  await NotificationService.initialize();
  // Prepare sound effects in the background; startup never waits for audio.
  unawaited(AudioService.instance.initialize());

  // Remove splash screen
  FlutterNativeSplash.remove();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: IcosApp(showFreshStartNotice: showFreshStartNotice),
    ),
  );
}
