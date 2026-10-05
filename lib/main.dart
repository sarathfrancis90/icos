import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/services/analytics_service.dart';
import 'core/services/audio_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/session_service.dart';
import 'core/services/storage_service.dart';
import 'core/services/supabase_service.dart';

Future<void> main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  // Keep semantics tree alive so accessibility tools (and Maestro E2E) can see widgets.
  // The handle must be stored to prevent garbage collection.
  // ignore: unused_local_variable
  final semanticsHandle = SemanticsBinding.instance.ensureSemantics();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

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
  await SupabaseService.initialize();

  // Per-user local data follows the signed-in user. Registered before anything
  // else listens so the scope is already switched when providers react.
  await StorageService.setActiveUser(SupabaseService.auth.currentUser?.id);
  SupabaseService.auth.onAuthStateChange.listen(
    (state) => StorageService.setActiveUser(state.session?.user.id),
    onError: (Object _) {},
  );

  // Guest session if there is none. Startup waits at most 5 s; the attempt
  // keeps going in the background and is retried on reconnect, on resume and
  // before the sync queue runs (see SessionKeeper).
  await SessionEnsurer.instance.ensureSession().timeout(
        const Duration(seconds: 5),
        onTimeout: () => false,
      );
  await StorageService.setActiveUser(SupabaseService.auth.currentUser?.id);

  // Notifications (local reminders + optional FCM); never throws.
  await NotificationService.initialize();
  // Pre-load sound effects.
  await AudioService.instance.initialize();

  // Remove splash screen
  FlutterNativeSplash.remove();

  runApp(
    const ProviderScope(
      child: IcosApp(),
    ),
  );
}
