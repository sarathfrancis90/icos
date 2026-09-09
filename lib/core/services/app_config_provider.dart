import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'app_config_service.dart';

part 'app_config_provider.g.dart';

/// Remote app configuration. Cached for the app lifetime; never throws
/// (falls back to [AppConfig.defaults]). Call
/// `ref.invalidate(appConfigProvider)` on app resume to refresh.
@Riverpod(keepAlive: true)
Future<AppConfig> appConfig(Ref ref) => AppConfigService.fetch();

/// Current app version (`1.2.3`) without build number.
@Riverpod(keepAlive: true)
Future<String> currentAppVersion(Ref ref) async {
  try {
    final info = await PackageInfo.fromPlatform();
    return info.version;
  } catch (_) {
    return '0.0.0';
  }
}

/// Human-readable version string, e.g. `1.0.0 (2)`.
@Riverpod(keepAlive: true)
Future<String> appVersionLabel(Ref ref) async {
  try {
    final info = await PackageInfo.fromPlatform();
    return '${info.version} (${info.buildNumber})';
  } catch (_) {
    return 'Unknown';
  }
}

/// Gate state derived from [appConfigProvider] + [currentAppVersionProvider].
enum AppGate { ok, forceUpdate, maintenance }

/// Resolves to [AppGate.ok] while loading so the app is never blocked by a
/// slow or failing config fetch.
@Riverpod(keepAlive: true)
AppGate appGate(Ref ref) {
  final config = ref.watch(appConfigProvider).valueOrNull;
  final version = ref.watch(currentAppVersionProvider).valueOrNull;
  if (config == null) return AppGate.ok;
  if (config.maintenanceMode) return AppGate.maintenance;
  if (version != null && config.isUpdateRequired(version)) {
    return AppGate.forceUpdate;
  }
  return AppGate.ok;
}
