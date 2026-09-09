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

  static int get solveCount => _prefs.getInt('solve_count') ?? 0;
  static Future<bool> incrementSolveCount() =>
      _prefs.setInt('solve_count', solveCount + 1);

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
  static Box<String> get syncQueue => _syncQueue;

  static int get syncQueueLength => _syncQueue.length;

  static Future<void> addToSyncQueue(Map<String, dynamic> item) async {
    // Millisecond timestamp + sequence keeps insertion order and uniqueness.
    final base = DateTime.now().millisecondsSinceEpoch;
    var key = base.toString().padLeft(14, '0');
    var seq = 0;
    while (_syncQueue.containsKey(key)) {
      seq++;
      key = '${base.toString().padLeft(14, '0')}-$seq';
    }
    await _syncQueue.put(key, jsonEncode(item));
  }

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

  // Game state persistence
  static Future<void> saveGameState(
    String key,
    Map<String, dynamic> state,
  ) async {
    await _prefs.setString('game_state_$key', jsonEncode(state));
  }

  static Map<String, dynamic>? getGameState(String key) {
    final data = _prefs.getString('game_state_$key');
    if (data == null) return null;
    return jsonDecode(data) as Map<String, dynamic>;
  }

  static Future<void> clearGameState(String key) async {
    await _prefs.remove('game_state_$key');
  }

  // Puzzle sessions (start-puzzle nonce per date)
  static String? getSessionNonce(String date) =>
      _prefs.getString('session_nonce_$date');

  static Future<void> saveSessionNonce(String date, String nonce) =>
      _prefs.setString('session_nonce_$date', nonce);

  // Submission results per date (see SubmissionResult in features/puzzle/data)
  static Map<String, dynamic>? getSubmissionResult(String date) {
    final data = _prefs.getString('submit_result_$date');
    if (data == null) return null;
    return jsonDecode(data) as Map<String, dynamic>;
  }

  static Future<void> saveSubmissionResult(
    String date,
    Map<String, dynamic> result,
  ) =>
      _prefs.setString('submit_result_$date', jsonEncode(result));

  static Future<void> clearSubmissionResult(String date) =>
      _prefs.remove('submit_result_$date');

  /// All dates that have a locally stored submission result.
  static Iterable<String> submissionResultDates() => _prefs
      .getKeys()
      .where((k) => k.startsWith('submit_result_'))
      .map((k) => k.substring('submit_result_'.length));

  // Practice stats
  static Map<String, dynamic> get practiceStats {
    final data = _prefs.getString('practice_stats');
    if (data == null) return {};
    return jsonDecode(data) as Map<String, dynamic>;
  }

  static Future<void> savePracticeStats(Map<String, dynamic> stats) =>
      _prefs.setString('practice_stats', jsonEncode(stats));
}
