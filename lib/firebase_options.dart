import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Firebase options sourced from the active `.env.*` file instead of
/// `flutterfire configure` codegen, so no secrets are committed.
///
/// Required keys (all must be non-empty for [isConfigured] to be true):
/// `FIREBASE_PROJECT_ID`, `FIREBASE_MESSAGING_SENDER_ID`,
/// `FIREBASE_ANDROID_API_KEY`, `FIREBASE_ANDROID_APP_ID`,
/// `FIREBASE_IOS_API_KEY`, `FIREBASE_IOS_APP_ID`, `FIREBASE_IOS_BUNDLE_ID`.
abstract final class DefaultFirebaseOptions {
  static const requiredKeys = [
    'FIREBASE_PROJECT_ID',
    'FIREBASE_MESSAGING_SENDER_ID',
    'FIREBASE_ANDROID_API_KEY',
    'FIREBASE_ANDROID_APP_ID',
    'FIREBASE_IOS_API_KEY',
    'FIREBASE_IOS_APP_ID',
    'FIREBASE_IOS_BUNDLE_ID',
  ];

  static String _env(String key) {
    try {
      if (!dotenv.isInitialized) return '';
      return (dotenv.env[key] ?? '').trim();
    } catch (_) {
      return '';
    }
  }

  /// True when every required env value is present. Pure function of the
  /// provided [env] map so it can be unit tested without dotenv.
  static bool isConfiguredFrom(Map<String, String> env) {
    for (final key in requiredKeys) {
      final value = env[key];
      if (value == null || value.trim().isEmpty) return false;
    }
    return true;
  }

  static bool get isConfigured {
    try {
      if (!dotenv.isInitialized) return false;
      return isConfiguredFrom(dotenv.env);
    } catch (_) {
      return false;
    }
  }

  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError('Firebase web is not configured for Icos.');
    }
    if (Platform.isAndroid) return android;
    if (Platform.isIOS) return ios;
    throw UnsupportedError(
      'DefaultFirebaseOptions are not supported for this platform.',
    );
  }

  static FirebaseOptions get android => FirebaseOptions(
        apiKey: _env('FIREBASE_ANDROID_API_KEY'),
        appId: _env('FIREBASE_ANDROID_APP_ID'),
        messagingSenderId: _env('FIREBASE_MESSAGING_SENDER_ID'),
        projectId: _env('FIREBASE_PROJECT_ID'),
        storageBucket: _optional('FIREBASE_STORAGE_BUCKET'),
      );

  static FirebaseOptions get ios => FirebaseOptions(
        apiKey: _env('FIREBASE_IOS_API_KEY'),
        appId: _env('FIREBASE_IOS_APP_ID'),
        messagingSenderId: _env('FIREBASE_MESSAGING_SENDER_ID'),
        projectId: _env('FIREBASE_PROJECT_ID'),
        storageBucket: _optional('FIREBASE_STORAGE_BUCKET'),
        iosBundleId: _env('FIREBASE_IOS_BUNDLE_ID'),
        iosClientId: _optional('GOOGLE_IOS_CLIENT_ID'),
      );

  static String? _optional(String key) {
    final v = _env(key);
    return v.isEmpty ? null : v;
  }
}
