import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import 'app_logger.dart';
import 'supabase_service.dart';

/// Remote application configuration stored in the public `app_config`
/// table (`key text pk, value jsonb`).
@immutable
class AppConfig {
  const AppConfig({
    this.minSupportedVersion = '0.0.0',
    this.latestVersion = '0.0.0',
    this.maintenanceMode = false,
    this.maintenanceMessage,
    this.storeUrls = const {},
  });

  /// Defaults used when the table cannot be read.
  static const AppConfig defaults = AppConfig();

  final String minSupportedVersion;
  final String latestVersion;
  final bool maintenanceMode;
  final String? maintenanceMessage;

  /// Platform → store URL, keys `android` and `ios`.
  final Map<String, String> storeUrls;

  static const androidPlayStoreFallback =
      'https://play.google.com/store/apps/details?id=com.icos.app';
  static const iosAppStoreFallback = 'https://apps.apple.com/app/icos';

  /// Store URL for the current platform (or [platformOverride] in tests).
  String storeUrlFor([String? platformOverride]) {
    final platform = platformOverride ??
        (kIsWeb
            ? 'web'
            : Platform.isIOS
                ? 'ios'
                : Platform.isAndroid
                    ? 'android'
                    : 'other');
    final url = storeUrls[platform];
    if (url != null && url.isNotEmpty) return url;
    return switch (platform) {
      'ios' => iosAppStoreFallback,
      _ => androidPlayStoreFallback,
    };
  }

  /// True when [currentVersion] is below [minSupportedVersion].
  bool isUpdateRequired(String currentVersion) =>
      compareVersions(currentVersion, minSupportedVersion) < 0;

  /// True when a newer (optional) version is available.
  bool isUpdateAvailable(String currentVersion) =>
      compareVersions(currentVersion, latestVersion) < 0;

  /// Builds an [AppConfig] from `app_config` rows (`{key, value}`).
  /// Tolerant of missing keys and loosely-typed values.
  factory AppConfig.fromRows(List<Map<String, dynamic>> rows) {
    final map = <String, dynamic>{};
    for (final row in rows) {
      final key = row['key'];
      if (key is String) map[key] = row['value'];
    }
    return AppConfig.fromMap(map);
  }

  factory AppConfig.fromMap(Map<String, dynamic> map) {
    final maintenance = map['maintenance_mode'];
    bool maintenanceMode = false;
    String? maintenanceMessage;
    if (maintenance is bool) {
      maintenanceMode = maintenance;
    } else if (maintenance is String) {
      maintenanceMode = maintenance.toLowerCase() == 'true';
    } else if (maintenance is Map) {
      final enabled = maintenance['enabled'];
      maintenanceMode = enabled == true ||
          (enabled is String && enabled.toLowerCase() == 'true');
      final msg = maintenance['message'];
      if (msg is String && msg.trim().isNotEmpty) maintenanceMessage = msg;
    }

    final urls = <String, String>{};
    final rawUrls = map['store_urls'];
    if (rawUrls is Map) {
      for (final entry in rawUrls.entries) {
        final k = entry.key;
        final v = entry.value;
        if (k is String && v is String && v.isNotEmpty) urls[k] = v;
      }
    }

    return AppConfig(
      minSupportedVersion: _versionString(map['min_supported_version']),
      latestVersion: _versionString(map['latest_version']),
      maintenanceMode: maintenanceMode,
      maintenanceMessage: maintenanceMessage,
      storeUrls: urls,
    );
  }

  static String _versionString(Object? value) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    if (value is Map && value['version'] is String) {
      return (value['version'] as String).trim();
    }
    return '0.0.0';
  }

  /// Semantic version compare. Ignores build metadata (`+2`) and treats a
  /// pre-release (`1.0.0-beta`) as lower than the release. Missing
  /// components are treated as zero (`1.2` == `1.2.0`).
  /// Returns negative when a < b, zero when equal, positive when a > b.
  static int compareVersions(String a, String b) {
    final pa = _parse(a);
    final pb = _parse(b);
    final len = pa.numbers.length > pb.numbers.length
        ? pa.numbers.length
        : pb.numbers.length;
    for (var i = 0; i < len; i++) {
      final x = i < pa.numbers.length ? pa.numbers[i] : 0;
      final y = i < pb.numbers.length ? pb.numbers[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    // Same numeric core: a release beats a pre-release.
    if (pa.preRelease == null && pb.preRelease == null) return 0;
    if (pa.preRelease == null) return 1;
    if (pb.preRelease == null) return -1;
    return pa.preRelease!.compareTo(pb.preRelease!);
  }

  static ({List<int> numbers, String? preRelease}) _parse(String v) {
    var s = v.trim();
    if (s.startsWith('v') || s.startsWith('V')) s = s.substring(1);
    final plus = s.indexOf('+');
    if (plus >= 0) s = s.substring(0, plus);
    String? pre;
    final dash = s.indexOf('-');
    if (dash >= 0) {
      pre = s.substring(dash + 1);
      s = s.substring(0, dash);
    }
    final numbers = s
        .split('.')
        .map((p) => int.tryParse(p.trim()) ?? 0)
        .toList(growable: false);
    return (numbers: numbers.isEmpty ? [0] : numbers, preRelease: pre);
  }

  @override
  bool operator ==(Object other) =>
      other is AppConfig &&
      other.minSupportedVersion == minSupportedVersion &&
      other.latestVersion == latestVersion &&
      other.maintenanceMode == maintenanceMode &&
      other.maintenanceMessage == maintenanceMessage &&
      mapEquals(other.storeUrls, storeUrls);

  @override
  int get hashCode => Object.hash(
        minSupportedVersion,
        latestVersion,
        maintenanceMode,
        maintenanceMessage,
        Object.hashAll(storeUrls.entries.map((e) => '${e.key}=${e.value}')),
      );

  @override
  String toString() =>
      'AppConfig(min: $minSupportedVersion, latest: $latestVersion, '
      'maintenance: $maintenanceMode, stores: $storeUrls)';
}

/// Fetches [AppConfig] from Supabase. Never throws.
abstract final class AppConfigService {
  static const Duration timeout = Duration(seconds: 5);

  static Future<AppConfig> fetch() async {
    try {
      final rows = await SupabaseService.client
          .from('app_config')
          .select('key, value')
          .timeout(timeout);
      return AppConfig.fromRows(List<Map<String, dynamic>>.from(rows));
    } catch (e, st) {
      AppLogger.warn('app_config fetch failed; using defaults',
          error: e, st: st);
      return AppConfig.defaults;
    }
  }
}
