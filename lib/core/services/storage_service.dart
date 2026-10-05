import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract final class StorageService {
  static late SharedPreferences _prefs;
  static late Box<String> _puzzleCache;
  static late Box<String> _syncQueue;

  /// Newest puzzles kept in the Hive cache (keys are ISO dates).
  static const int maxCachedPuzzles = 60;

  /// Queue entries belonging to another user are dropped after this long
  /// (the same window `submit-score` accepts).
  static const Duration syncEntryMaxAge = Duration(days: 7);

  // ─── Per-user scope ────────────────────────────────────────────────
  //
  // Everything about a player (results, game state, session nonces, solve
  // count, practice stats, queued submissions) is keyed by the Supabase user
  // id so a different account on the same device never sees it. Device
  // settings (theme, onboarding, ...) stay global. The key prefix is a cached
  // string: building a key is concatenation only, no I/O.

  static const String _migrationFlag = 'local_scope_migrated_v1';
  static const String _noUserScope = 'u.none.';

  /// Key prefixes / names that hold per-player data in un-scoped (pre-1.0.x)
  /// storage. Anything else in SharedPreferences is a device setting.
  static const List<String> _legacyPlayerPrefixes = [
    'game_state_',
    'session_nonce_',
    'submit_result_',
  ];
  static const List<String> _legacyPlayerKeys = ['solve_count', 'practice_stats'];

  static String? _userId;
  static String _prefix = _noUserScope;

  /// The user whose records are currently read and written, or `null` while
  /// there is no session.
  static String? get activeUserId => _userId;

  /// Switches the active player. Call at startup and on every auth change.
  ///
  /// The scope changes synchronously; the adoption work that follows is
  /// idempotent:
  ///  * records stored before scoping existed are adopted once (flag in
  ///    SharedPreferences), by the first signed-in user;
  ///  * records made while no session existed (offline first launch) are
  ///    adopted by the next user that appears.
  /// Calling it again with the same id (linkIdentity / updateUser keep the
  /// user id) moves nothing.
  static Future<void> setActiveUser(String? userId) {
    _userId = userId;
    _prefix = userId == null ? _noUserScope : 'u.$userId.';
    if (userId == null) return Future.value();
    // Adoption runs one at a time and works from the user id and prefix
    // captured here, so a user change halfway cannot split records between
    // two users.
    final prefix = _prefix;
    final run = _adoption.then((_) => _adopt(userId, prefix));
    _adoption = run.then((_) {}, onError: (Object _) {});
    return run;
  }

  static Future<void> _adopt(String userId, String prefix) async {
    if (!(_prefs.getBool(_migrationFlag) ?? false)) {
      await _moveKeys(
        matches: (k) =>
            _legacyPlayerKeys.contains(k) ||
            _legacyPlayerPrefixes.any(k.startsWith),
        rename: (k) => '$prefix$k',
      );
      await _prefs.setBool(_migrationFlag, true);
    }
    await _moveKeys(
      matches: (k) => k.startsWith(_noUserScope),
      rename: (k) => '$prefix${k.substring(_noUserScope.length)}',
    );
    await stampOwnerlessQueueEntries(userId);
  }

  static Future<void> _adoption = Future.value();

  static String _prefixFor(String? userId) =>
      userId == null ? _prefix : 'u.$userId.';

  /// Removes everything stored for [userId] (e.g. after account deletion):
  /// results, game state, nonces, solve count, practice stats and queue
  /// entries. Other users and device settings are untouched.
  static Future<void> clearUserData(String userId) async {
    final prefix = 'u.$userId.';
    for (final key in _prefs.getKeys().where((k) => k.startsWith(prefix)).toList()) {
      await _prefs.remove(key);
    }
    for (final entry in getSyncQueueItems()) {
      if (entry.value['user_id'] == userId) {
        await _syncQueue.delete(entry.key);
      }
    }
  }

  /// Moves matching SharedPreferences entries to their new key. An existing
  /// value under the new key wins.
  static Future<void> _moveKeys({
    required bool Function(String key) matches,
    required String Function(String key) rename,
  }) async {
    for (final key in _prefs.getKeys().where(matches).toList()) {
      final target = rename(key);
      if (target != key && !_prefs.containsKey(target)) {
        final value = _prefs.get(key);
        switch (value) {
          case final String v:
            await _prefs.setString(target, v);
          case final int v:
            await _prefs.setInt(target, v);
          case final bool v:
            await _prefs.setBool(target, v);
          case final double v:
            await _prefs.setDouble(target, v);
          case final List<String> v:
            await _prefs.setStringList(target, v);
        }
      }
      await _prefs.remove(key);
    }
  }

  static Future<void> initialize() async {
    await Hive.initFlutter();
    _prefs = await SharedPreferences.getInstance();
    _puzzleCache = await Hive.openBox<String>('puzzle_cache');
    _syncQueue = await Hive.openBox<String>('sync_queue');
  }

  /// Test-only initialiser: uses the given [SharedPreferences] (typically
  /// created after `SharedPreferences.setMockInitialValues`) and a Hive
  /// directory under [hivePath] (e.g. a temp dir). Boxes are opened fresh.
  @visibleForTesting
  static Future<void> initializeForTest({
    required String hivePath,
    required SharedPreferences prefs,
  }) async {
    _prefs = prefs;
    Hive.init(hivePath);
    _puzzleCache = await Hive.openBox<String>('puzzle_cache_test');
    _syncQueue = await Hive.openBox<String>('sync_queue_test');
    await _puzzleCache.clear();
    await _syncQueue.clear();
    _userId = null;
    _prefix = _noUserScope;
    _adoption = Future.value();
  }

  // SharedPreferences - User Settings
  static SharedPreferences get prefs => _prefs;

  static bool get isDarkMode => _prefs.getBool('dark_mode') ?? true;
  static Future<bool> setDarkMode(bool value) =>
      _prefs.setBool('dark_mode', value);

  static String get themeMode => _prefs.getString('theme_mode') ?? 'system';
  static Future<bool> setThemeMode(String value) =>
      _prefs.setString('theme_mode', value);

  static bool get hapticEnabled => _prefs.getBool('haptic_enabled') ?? true;
  static Future<bool> setHapticEnabled(bool value) =>
      _prefs.setBool('haptic_enabled', value);

  static bool get soundEnabled => _prefs.getBool('sound_enabled') ?? true;
  static Future<bool> setSoundEnabled(bool value) =>
      _prefs.setBool('sound_enabled', value);

  static String get colorblindMode =>
      _prefs.getString('colorblind_mode') ?? 'none';
  static Future<bool> setColorblindMode(String value) =>
      _prefs.setString('colorblind_mode', value);

  static int get solveCount => _prefs.getInt('${_prefix}solve_count') ?? 0;
  static Future<bool> incrementSolveCount() =>
      _prefs.setInt('${_prefix}solve_count', solveCount + 1);

  static bool get hasSeenOnboarding =>
      _prefs.getBool('has_seen_onboarding') ?? false;
  static Future<bool> setHasSeenOnboarding(bool value) =>
      _prefs.setBool('has_seen_onboarding', value);

  static bool get hasSeenNotificationPrompt =>
      _prefs.getBool('has_seen_notification_prompt') ?? false;
  static Future<bool> setHasSeenNotificationPrompt(bool value) =>
      _prefs.setBool('has_seen_notification_prompt', value);

  static bool get hasRequestedReview =>
      _prefs.getBool('has_requested_review') ?? false;
  static Future<bool> setHasRequestedReview(bool value) =>
      _prefs.setBool('has_requested_review', value);

  // Hive - Puzzle Cache
  static Box<String> get puzzleCache => _puzzleCache;

  static Future<void> cachePuzzle(
    String date,
    Map<String, dynamic> puzzleData,
  ) async {
    await _puzzleCache.put(date, jsonEncode(puzzleData));
    await _trimPuzzleCache();
  }

  static Map<String, dynamic>? getCachedPuzzle(String date) {
    final data = _puzzleCache.get(date);
    if (data == null) return null;
    try {
      return jsonDecode(data) as Map<String, dynamic>;
    } on FormatException {
      return null;
    }
  }

  /// Keeps only the newest [maxCachedPuzzles] dates (keys sort as ISO dates).
  static Future<void> _trimPuzzleCache() async {
    if (_puzzleCache.length <= maxCachedPuzzles) return;
    final keys = _puzzleCache.keys.map((k) => k.toString()).toList()..sort();
    final excess = keys.length - maxCachedPuzzles;
    await _puzzleCache.deleteAll(keys.take(excess));
  }

  // Hive - Sync Queue
  //
  // One device-wide box; every entry records the user it was created under
  // (`user_id`). The worker only submits entries for the signed-in user.
  static Box<String> get syncQueue => _syncQueue;

  /// Queued entries of the active user.
  static int get syncQueueLength => _syncQueue.values.where((raw) {
        try {
          return (jsonDecode(raw) as Map<String, dynamic>)['user_id'] ==
              _userId;
        } on FormatException {
          return false;
        }
      }).length;

  static Future<void> addToSyncQueue(Map<String, dynamic> item) async {
    // Millisecond timestamp + sequence keeps insertion order and uniqueness.
    final base = DateTime.now().millisecondsSinceEpoch;
    var key = base.toString().padLeft(14, '0');
    var seq = 0;
    while (_syncQueue.containsKey(key)) {
      seq++;
      key = '${base.toString().padLeft(14, '0')}-$seq';
    }
    final stamped = <String, dynamic>{
      ...item,
      'user_id': ?(item['user_id'] ?? _userId),
    };
    await _syncQueue.put(key, jsonEncode(stamped));
  }

  /// Every queued entry, whichever user created it, oldest first.
  static List<MapEntry<String, Map<String, dynamic>>> getSyncQueueItems() {
    final entries = _syncQueue.toMap().entries.map((e) {
      return MapEntry(
        e.key as String,
        jsonDecode(e.value) as Map<String, dynamic>,
      );
    }).toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return entries;
  }

  static Future<void> removeSyncQueueItem(String key) async {
    await _syncQueue.delete(key);
  }

  /// Gives entries without an owner (made before scoping existed, or before
  /// any session) to [userId].
  static Future<void> stampOwnerlessQueueEntries(String userId) async {
    for (final entry in getSyncQueueItems()) {
      if (entry.value['user_id'] != null) continue;
      await _syncQueue.put(
        entry.key,
        jsonEncode({...entry.value, 'user_id': userId}),
      );
    }
  }

  /// Drops entries that belong to another user and are older than
  /// [syncEntryMaxAge]. Those would be rejected by the server's date window
  /// anyway; they are kept until then so the owner can still sync them after
  /// signing back in.
  static Future<void> purgeStaleForeignSyncEntries({DateTime? now}) async {
    final cutoff = (now ?? DateTime.now()).subtract(syncEntryMaxAge);
    for (final entry in getSyncQueueItems()) {
      final owner = entry.value['user_id'];
      if (owner == null || owner == _userId) continue;
      final millis = int.tryParse(entry.key.split('-').first);
      if (millis == null) continue;
      if (DateTime.fromMillisecondsSinceEpoch(millis).isBefore(cutoff)) {
        await _syncQueue.delete(entry.key);
      }
    }
  }

  // Game state persistence
  static Future<void> saveGameState(
    String key,
    Map<String, dynamic> state,
  ) async {
    await _prefs.setString('${_prefix}game_state_$key', jsonEncode(state));
  }

  static Map<String, dynamic>? getGameState(String key) {
    final data = _prefs.getString('${_prefix}game_state_$key');
    if (data == null) return null;
    return jsonDecode(data) as Map<String, dynamic>;
  }

  static Future<void> clearGameState(String key) async {
    await _prefs.remove('${_prefix}game_state_$key');
  }

  // Puzzle sessions (start-puzzle nonce per date)
  //
  // Reads and writes after an `await` should pass the [userId] that started
  // the operation: the active user may have changed in the meantime.
  static String? getSessionNonce(String date, {String? userId}) =>
      _prefs.getString('${_prefixFor(userId)}session_nonce_$date');

  static Future<void> saveSessionNonce(
    String date,
    String nonce, {
    String? userId,
  }) =>
      _prefs.setString('${_prefixFor(userId)}session_nonce_$date', nonce);

  // Submission results per date (see SubmissionResult in features/puzzle/data)
  static Map<String, dynamic>? getSubmissionResult(
    String date, {
    String? userId,
  }) {
    final data = _prefs.getString('${_prefixFor(userId)}submit_result_$date');
    if (data == null) return null;
    return jsonDecode(data) as Map<String, dynamic>;
  }

  static Future<void> saveSubmissionResult(
    String date,
    Map<String, dynamic> result, {
    String? userId,
  }) =>
      _prefs.setString(
        '${_prefixFor(userId)}submit_result_$date',
        jsonEncode(result),
      );

  static Future<void> clearSubmissionResult(String date) =>
      _prefs.remove('${_prefix}submit_result_$date');

  /// All dates that have a locally stored submission result.
  static Iterable<String> submissionResultDates() {
    final start = '${_prefix}submit_result_';
    return _prefs
        .getKeys()
        .where((k) => k.startsWith(start))
        .map((k) => k.substring(start.length));
  }

  // Solves of a bundled (offline) puzzle. Kept apart from daily results so
  // they can never block or overwrite the result for the real puzzle of that
  // date, and are never submitted or counted.
  static Map<String, dynamic>? getBundledResult(String date) {
    final data = _prefs.getString('${_prefix}bundled_result_$date');
    if (data == null) return null;
    return jsonDecode(data) as Map<String, dynamic>;
  }

  static Future<void> saveBundledResult(
    String date,
    Map<String, dynamic> result,
  ) =>
      _prefs.setString('${_prefix}bundled_result_$date', jsonEncode(result));

  // Practice stats
  static Map<String, dynamic> get practiceStats {
    final data = _prefs.getString('${_prefix}practice_stats');
    if (data == null) return {};
    return jsonDecode(data) as Map<String, dynamic>;
  }

  static Future<void> savePracticeStats(Map<String, dynamic> stats) =>
      _prefs.setString('${_prefix}practice_stats', jsonEncode(stats));
}
