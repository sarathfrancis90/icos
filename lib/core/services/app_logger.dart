import 'dart:convert';
import 'dart:developer' as developer;

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Severity levels for [AppLogger].
enum LogLevel { debug, info, warn, error }

/// Structured logger used across the app.
///
/// - In debug builds every entry is emitted as a JSON line through
///   `dart:developer` so it shows up in DevTools / `flutter run` output.
/// - When Firebase is initialised (see `AnalyticsService.initialize`),
///   `warn` and `error` entries are forwarded to Crashlytics as non-fatal
///   errors so they can be triaged in production.
abstract final class AppLogger {
  /// Whether Crashlytics forwarding is active. Set by `AnalyticsService`
  /// after a successful `Firebase.initializeApp`.
  static bool crashlyticsEnabled = false;

  /// Optional sink for tests: receives every structured entry.
  @visibleForTesting
  static void Function(Map<String, Object?> entry)? testSink;

  static void log(
    String message, {
    LogLevel level = LogLevel.info,
    Object? error,
    StackTrace? st,
    Map<String, Object?>? data,
  }) {
    final entry = <String, Object?>{
      'ts': DateTime.now().toUtc().toIso8601String(),
      'level': level.name,
      'message': message,
      if (data != null && data.isNotEmpty) 'data': data,
      if (error != null) 'error': error.toString(),
    };

    testSink?.call(entry);

    if (kDebugMode) {
      developer.log(
        _encode(entry),
        name: 'icos',
        level: _developerLevel(level),
        error: error,
        stackTrace: st,
      );
    }

    if (crashlyticsEnabled &&
        (level == LogLevel.error || level == LogLevel.warn)) {
      _forwardToCrashlytics(message, level, error, st, data);
    }
  }

  static void debug(
    String message, {
    Object? error,
    StackTrace? st,
    Map<String, Object?>? data,
  }) =>
      log(message, level: LogLevel.debug, error: error, st: st, data: data);

  static void info(
    String message, {
    Object? error,
    StackTrace? st,
    Map<String, Object?>? data,
  }) =>
      log(message, level: LogLevel.info, error: error, st: st, data: data);

  static void warn(
    String message, {
    Object? error,
    StackTrace? st,
    Map<String, Object?>? data,
  }) =>
      log(message, level: LogLevel.warn, error: error, st: st, data: data);

  static void error(
    String message, {
    Object? error,
    StackTrace? st,
    Map<String, Object?>? data,
  }) =>
      log(message, level: LogLevel.error, error: error, st: st, data: data);

  static void _forwardToCrashlytics(
    String message,
    LogLevel level,
    Object? error,
    StackTrace? st,
    Map<String, Object?>? data,
  ) {
    try {
      final crashlytics = FirebaseCrashlytics.instance;
      crashlytics.log('[${level.name}] $message');
      if (error != null || level == LogLevel.error) {
        crashlytics.recordError(
          error ?? message,
          st,
          reason: message,
          information: [
            if (data != null)
              for (final e in data.entries) '${e.key}=${e.value}',
          ],
          fatal: false,
        );
      }
    } catch (_) {
      // Never let logging crash the app.
    }
  }

  static String _encode(Map<String, Object?> entry) {
    try {
      return jsonEncode(entry);
    } catch (_) {
      return entry.toString();
    }
  }

  static int _developerLevel(LogLevel level) => switch (level) {
        LogLevel.debug => 500,
        LogLevel.info => 800,
        LogLevel.warn => 900,
        LogLevel.error => 1000,
      };
}
