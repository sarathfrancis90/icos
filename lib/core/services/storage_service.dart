import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract final class StorageService {
  static late final SharedPreferences _prefs;
  static late final Box<String> _puzzleCache;
  static late final Box<String> _syncQueue;

  static Future<void> initialize() async {
    await Hive.initFlutter();
    _prefs = await SharedPreferences.getInstance();
    _puzzleCache = await Hive.openBox<String>('puzzle_cache');
    _syncQueue = await Hive.openBox<String>('sync_queue');
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

  // Hive - Puzzle Cache
  static Box<String> get puzzleCache => _puzzleCache;

  static Future<void> cachePuzzle(
    String date,
    Map<String, dynamic> puzzleData,
  ) async {
    await _puzzleCache.put(date, jsonEncode(puzzleData));
  }

  static Map<String, dynamic>? getCachedPuzzle(String date) {
    final data = _puzzleCache.get(date);
    if (data == null) return null;
    return jsonDecode(data) as Map<String, dynamic>;
  }

  // Hive - Sync Queue
  static Box<String> get syncQueue => _syncQueue;

  static Future<void> addToSyncQueue(Map<String, dynamic> item) async {
    final key = DateTime.now().millisecondsSinceEpoch.toString();
    await _syncQueue.put(key, jsonEncode(item));
  }

  static List<MapEntry<String, Map<String, dynamic>>> getSyncQueueItems() {
    return _syncQueue.toMap().entries.map((e) {
      return MapEntry(
        e.key as String,
        jsonDecode(e.value) as Map<String, dynamic>,
      );
    }).toList();
  }

  static Future<void> removeSyncQueueItem(String key) async {
    await _syncQueue.delete(key);
  }

  // Game state persistence
  static Future<void> saveGameState(
    String puzzleDate,
    Map<String, dynamic> state,
  ) async {
    await _prefs.setString('game_state_$puzzleDate', jsonEncode(state));
  }

  static Map<String, dynamic>? getGameState(String puzzleDate) {
    final data = _prefs.getString('game_state_$puzzleDate');
    if (data == null) return null;
    return jsonDecode(data) as Map<String, dynamic>;
  }

  static Future<void> clearGameState(String puzzleDate) async {
    await _prefs.remove('game_state_$puzzleDate');
  }
}
