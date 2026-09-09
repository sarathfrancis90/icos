import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import '../../firebase_options.dart';
import 'app_logger.dart';

/// Event taxonomy. Keep names snake_case and <= 40 chars (GA4 limit).
abstract final class AnalyticsEvents {
  static const puzzleStart = 'puzzle_start';

  /// params: time_seconds, hints, undos, difficulty, grid
  static const puzzleComplete = 'puzzle_complete';
  static const hintUsed = 'hint_used';
  static const groupCreate = 'group_create';
  static const groupJoin = 'group_join';
  static const shareResult = 'share_result';

  /// params: method (email | google | apple)
  static const accountCreate = 'account_create';

  /// params: method (email | google | apple)
  static const signIn = 'sign_in';
  static const signOut = 'sign_out';
  static const notificationOptIn = 'notification_opt_in';
  static const notificationOptOut = 'notification_opt_out';
  static const accountDeleteRequested = 'account_delete_requested';
  static const accountDeleteCancelled = 'account_delete_cancelled';
  static const dataExport = 'data_export';
  static const displayNameChanged = 'display_name_changed';
}

/// Analytics + crash reporting facade.
///
/// When Firebase env values are missing ([DefaultFirebaseOptions.isConfigured]
/// is false) every method is a cheap no-op so the app runs identically in
/// local/dev builds without a Firebase project.
abstract final class AnalyticsService {
  static bool _initialized = false;
  static bool _enabled = false;

  /// Whether Firebase was initialised successfully.
  static bool get isEnabled => _enabled;

  /// Test hook: records every event that would have been sent.
  @visibleForTesting
  static List<({String name, Map<String, Object>? params})>? testEvents;

  /// Initialise Firebase (Analytics + Crashlytics). Safe to call once from
  /// `main()`; never throws.
  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    if (!DefaultFirebaseOptions.isConfigured) {
      AppLogger.info('Firebase not configured; analytics disabled');
      return;
    }

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
      _enabled = true;
      AppLogger.crashlyticsEnabled = true;

      final crashlytics = FirebaseCrashlytics.instance;
      await crashlytics.setCrashlyticsCollectionEnabled(!kDebugMode);

      // Route Flutter framework errors to Crashlytics.
      final previousOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        previousOnError?.call(details);
        crashlytics.recordFlutterFatalError(details);
      };

      // Route uncaught async errors (outside the Flutter framework).
      PlatformDispatcher.instance.onError = (error, stack) {
        crashlytics.recordError(error, stack, fatal: true);
        return true;
      };

      await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(true);
      AppLogger.info('Firebase initialised');
    } catch (e, st) {
      _enabled = false;
      AppLogger.crashlyticsEnabled = false;
      AppLogger.warn('Firebase initialisation failed', error: e, st: st);
    }
  }

  static Future<void> logEvent(
    String name, [
    Map<String, Object>? params,
  ]) async {
    testEvents?.add((name: name, params: params));
    AppLogger.debug('analytics:$name', data: params);
    if (!_enabled) return;
    try {
      await FirebaseAnalytics.instance.logEvent(name: name, parameters: params);
    } catch (e) {
      AppLogger.debug('analytics logEvent failed', error: e);
    }
  }

  static Future<void> setUserId(String? userId) async {
    if (!_enabled) return;
    try {
      await FirebaseAnalytics.instance.setUserId(id: userId);
      await FirebaseCrashlytics.instance.setUserIdentifier(userId ?? '');
    } catch (e) {
      AppLogger.debug('analytics setUserId failed', error: e);
    }
  }

  static Future<void> logScreen(String screenName) async {
    AppLogger.debug('screen:$screenName');
    if (!_enabled) return;
    try {
      await FirebaseAnalytics.instance.logScreenView(screenName: screenName);
    } catch (e) {
      AppLogger.debug('analytics logScreen failed', error: e);
    }
  }
}
