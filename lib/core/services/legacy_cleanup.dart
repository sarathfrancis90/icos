import 'package:shared_preferences/shared_preferences.dart';

/// One-time cleanup for installs upgrading from the Supabase-backed 1.0.x
/// builds (design §9.2). Nothing is migrated: the old session keys are
/// removed, the local caches are cleared and the caller shows the
/// fresh-start notice once.
abstract final class LegacyCleanup {
  /// Set when legacy state was found and cleared; the notice is due once.
  static const String noticeShownKey = 'fresh_start_notice_shown';

  /// Set on the first launch of this version, legacy or not, so data the
  /// new backend stores later is never mistaken for legacy state.
  static const String checkedKey = 'legacy_cleanup_checked_v1';

  /// The Supabase client's session key (older SDKs used one fixed key; newer
  /// ones `sb-<project-ref>-auth-token` and friends).
  static const String _supabaseSessionKey = 'supabase.auth.token';
  static const String _supabaseKeyPrefix = 'sb-';

  /// Written by `StorageService` once a 1.0.x user's records were scoped.
  static const String _scopeMarkerKey = 'local_scope_migrated_v1';

  /// Prefix of per-user records (`u.<user id>.…`).
  static const String _userScopePrefix = 'u.';

  static bool _isSupabaseKey(String key) =>
      key == _supabaseSessionKey || key.startsWith(_supabaseKeyPrefix);

  /// Returns `true` exactly once, on the first launch that finds legacy
  /// state: a Supabase session key, the old per-user storage in
  /// SharedPreferences, or ([hasLegacyHiveData]) records in the Hive boxes.
  /// Fresh installs and every later launch return `false`.
  ///
  /// [clearCaches] wipes the puzzle cache, sync queue and per-user results;
  /// a failure there does not stop the cleanup. Any SharedPreferences
  /// failure returns `false` (no notice) instead of throwing.
  static Future<bool> runIfNeeded(
    SharedPreferences prefs, {
    Future<void> Function()? clearCaches,
    bool Function()? hasLegacyHiveData,
  }) async {
    try {
      return await _run(prefs, clearCaches, hasLegacyHiveData);
    } catch (_) {
      // A storage failure must never stop startup; no notice this launch.
      return false;
    }
  }

  static Future<bool> _run(
    SharedPreferences prefs,
    Future<void> Function()? clearCaches,
    bool Function()? hasLegacyHiveData,
  ) async {
    if ((prefs.getBool(checkedKey) ?? false) ||
        (prefs.getBool(noticeShownKey) ?? false)) {
      return false;
    }

    final keys = prefs.getKeys();
    final supabaseKeys = keys.where(_isSupabaseKey).toList();
    final legacy = supabaseKeys.isNotEmpty ||
        keys.contains(_scopeMarkerKey) ||
        keys.any((k) => k.startsWith(_userScopePrefix)) ||
        (hasLegacyHiveData?.call() ?? false);

    if (legacy) {
      for (final key in supabaseKeys) {
        await prefs.remove(key);
      }
      if (clearCaches != null) {
        try {
          await clearCaches();
        } catch (_) {
          // Stale caches are harmless next to a notice shown on every launch.
        }
      }
      await prefs.setBool(noticeShownKey, true);
    }
    await prefs.setBool(checkedKey, true);
    return legacy;
  }
}
