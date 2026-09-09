import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'analytics_service.dart';
import 'app_logger.dart';

/// Local + push notifications.
///
/// - Daily reminder: repeating local notification at a user-chosen local
///   time (default 09:00). Persisted in SharedPreferences.
/// - Streak-at-risk: one-shot local notification at 20:00 local today, meant
///   to be scheduled by the puzzle feature when today's puzzle is unsolved
///   and cancelled once it is solved.
/// - FCM: subscribes to the `daily_puzzle` topic when Firebase is configured.
abstract final class NotificationService {
  static const int dailyReminderId = 1;
  static const int streakReminderId = 2;

  static const String _prefEnabled = 'notif_daily_enabled';
  static const String _prefHour = 'notif_daily_hour';
  static const String _prefMinute = 'notif_daily_minute';

  static const TimeOfDay defaultReminderTime = TimeOfDay(hour: 9, minute: 0);
  static const TimeOfDay streakReminderTime = TimeOfDay(hour: 20, minute: 0);

  static const String dailyPuzzleTopic = 'daily_puzzle';

  static const AndroidNotificationDetails _androidDaily =
      AndroidNotificationDetails(
    'daily_reminder',
    'Daily puzzle reminder',
    channelDescription: 'Reminds you to play today\'s puzzle',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
  );

  static const AndroidNotificationDetails _androidStreak =
      AndroidNotificationDetails(
    'streak_reminder',
    'Streak at risk',
    channelDescription: 'Warns you before your streak resets at midnight UTC',
    importance: Importance.high,
    priority: Priority.high,
  );

  static const DarwinNotificationDetails _darwin = DarwinNotificationDetails(
    presentAlert: true,
    presentBadge: false,
    presentSound: true,
  );

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;
  static bool _timezoneReady = false;

  static bool get isInitialized => _initialized;

  /// Optional callback invoked when the user taps a notification. Payload is
  /// `daily` or `streak`; the router can navigate to `/`.
  static void Function(String? payload)? onNotificationTap;

  /// Initialise timezone db, the local notifications plugin and (optionally)
  /// FCM. Safe to call once from `main()`; never throws.
  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    await _ensureTimezone();

    try {
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      );
      await _plugin.initialize(
        settings: settings,
        onDidReceiveNotificationResponse: (response) {
          onNotificationTap?.call(response.payload);
        },
      );
    } catch (e, st) {
      AppLogger.warn('Local notifications init failed', error: e, st: st);
    }

    // Re-arm the daily reminder in case the OS dropped it (reboot etc.).
    try {
      if (await isEnabled()) {
        await scheduleDailyReminder(await reminderTime());
      }
    } catch (e, st) {
      AppLogger.warn('Re-scheduling daily reminder failed', error: e, st: st);
    }

    await _initFcm();
  }

  static Future<void> _ensureTimezone() async {
    if (_timezoneReady) return;
    try {
      tzdata.initializeTimeZones();
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (e) {
      // Fall back to UTC; scheduling still works, just in UTC.
      try {
        tz.setLocalLocation(tz.UTC);
      } catch (_) {}
      AppLogger.warn('Timezone resolution failed; using UTC', error: e);
    }
    _timezoneReady = true;
  }

  static Future<void> _initFcm() async {
    if (!AnalyticsService.isEnabled) return;
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.subscribeToTopic(dailyPuzzleTopic);
      AppLogger.info('Subscribed to FCM topic', data: {'topic': dailyPuzzleTopic});
    } catch (e, st) {
      AppLogger.warn('FCM setup failed', error: e, st: st);
    }
  }

  /// Requests OS notification permission. Returns true when granted (or
  /// when the platform does not require a runtime prompt).
  static Future<bool> requestPermission() async {
    var granted = true;
    try {
      if (!kIsWeb && Platform.isIOS) {
        final ios = _plugin.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
        granted = await ios?.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            ) ??
            false;
      } else if (!kIsWeb && Platform.isAndroid) {
        final android = _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        granted = await android?.requestNotificationsPermission() ?? true;
      }
    } catch (e, st) {
      AppLogger.warn('Notification permission request failed',
          error: e, st: st);
      granted = false;
    }

    if (AnalyticsService.isEnabled) {
      try {
        await FirebaseMessaging.instance.requestPermission();
      } catch (e) {
        AppLogger.debug('FCM permission request failed', error: e);
      }
    }

    await AnalyticsService.logEvent(
      granted
          ? AnalyticsEvents.notificationOptIn
          : AnalyticsEvents.notificationOptOut,
    );
    return granted;
  }

  // ─── Daily reminder ─────────────────────────────────────────────────

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefEnabled) ?? false;
  }

  static Future<TimeOfDay> reminderTime() async {
    final prefs = await SharedPreferences.getInstance();
    final hour = prefs.getInt(_prefHour) ?? defaultReminderTime.hour;
    final minute = prefs.getInt(_prefMinute) ?? defaultReminderTime.minute;
    return TimeOfDay(hour: hour, minute: minute);
  }

  /// Schedules (or re-schedules) the repeating daily reminder at [time]
  /// (device local time) and persists the preference.
  static Future<void> scheduleDailyReminder(TimeOfDay time) async {
    await _ensureTimezone();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefEnabled, true);
    await prefs.setInt(_prefHour, time.hour);
    await prefs.setInt(_prefMinute, time.minute);

    try {
      await _plugin.cancel(id: dailyReminderId);
      await _plugin.zonedSchedule(
        id: dailyReminderId,
        title: 'Today\'s Icos is ready',
        body: 'A fresh path awaits. Keep your streak alive!',
        scheduledDate: nextInstanceOf(time),
        notificationDetails: const NotificationDetails(
          android: _androidDaily,
          iOS: _darwin,
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: 'daily',
      );
      AppLogger.info('Daily reminder scheduled',
          data: {'hour': time.hour, 'minute': time.minute});
    } catch (e, st) {
      AppLogger.warn('Scheduling daily reminder failed', error: e, st: st);
    }
  }

  /// Cancels the daily reminder and persists the preference as disabled.
  static Future<void> cancelReminder() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefEnabled, false);
    try {
      await _plugin.cancel(id: dailyReminderId);
    } catch (e) {
      AppLogger.debug('Cancelling daily reminder failed', error: e);
    }
  }

  // ─── Streak at risk ─────────────────────────────────────────────────

  /// Schedules a one-shot "streak at risk" notification at 20:00 local
  /// today. No-op if that time has already passed. The puzzle feature should
  /// call this when today's puzzle is unsolved and [cancelStreakReminder]
  /// once it is solved.
  static Future<void> scheduleStreakReminder({int currentStreak = 0}) async {
    await _ensureTimezone();
    final now = tz.TZDateTime.now(tz.local);
    final at = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      streakReminderTime.hour,
      streakReminderTime.minute,
    );
    if (!at.isAfter(now)) return;

    final body = currentStreak > 0
        ? 'You haven\'t solved today\'s puzzle yet. Your $currentStreak-day '
            'streak resets at midnight UTC.'
        : 'You haven\'t solved today\'s puzzle yet. Play before midnight UTC!';

    try {
      await _plugin.cancel(id: streakReminderId);
      await _plugin.zonedSchedule(
        id: streakReminderId,
        title: 'Streak at risk',
        body: body,
        scheduledDate: at,
        notificationDetails: const NotificationDetails(
          android: _androidStreak,
          iOS: _darwin,
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: 'streak',
      );
    } catch (e, st) {
      AppLogger.warn('Scheduling streak reminder failed', error: e, st: st);
    }
  }

  static Future<void> cancelStreakReminder() async {
    try {
      await _plugin.cancel(id: streakReminderId);
    } catch (e) {
      AppLogger.debug('Cancelling streak reminder failed', error: e);
    }
  }

  /// Next occurrence of [time] in the local timezone (today if still ahead,
  /// otherwise tomorrow).
  @visibleForTesting
  static tz.TZDateTime nextInstanceOf(TimeOfDay time, {tz.TZDateTime? now}) {
    final current = now ?? tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      current.location,
      current.year,
      current.month,
      current.day,
      time.hour,
      time.minute,
    );
    if (!scheduled.isAfter(current)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }
}
