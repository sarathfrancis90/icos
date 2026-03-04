import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/services/storage_service.dart';
import 'core/services/supabase_service.dart';

Future<void> main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // Lock orientation to portrait on phones
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Load environment variables
  final envFile = kReleaseMode ? '.env.production' : '.env.development';
  await dotenv.load(fileName: envFile);

  // Initialize services
  await StorageService.initialize();
  await SupabaseService.initialize();

  // Auto sign in anonymously if no session exists
  if (SupabaseService.auth.currentSession == null) {
    try {
      await SupabaseService.auth
          .signInAnonymously()
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // Offline or timeout — continue without auth
    }
  }

  // Remove splash screen
  FlutterNativeSplash.remove();

  runApp(
    const ProviderScope(
      child: IcosApp(),
    ),
  );
}
