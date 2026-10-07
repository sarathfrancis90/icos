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
import 'streak_reminder_schedule.dart';

/// Local + push notifications.
///
/// - Daily reminder: repeating local notification at a user-chosen local
///   time (default 09:00). Persisted in SharedPreferences.
/// - Streak-at-risk: one-shot local notification 4 hours before the next
///   00:00 UTC (see [streakReminderFireTime]) while the player has a streak:
///   today's when today's puzzle is unsolved, tomorrow's once it is solved.
/// - Every scheduling path goes through [_mayNotify]: the in-app setting and
///   the OS permission must both be on, otherwise pending notifications of
///   that kind are cancelled instead.
/// - FCM: subscribes to the `daily_puzzle` topic when Firebase is configured.
abstract final class NotificationService {
  static const int dailyReminderId = 1;
  static const int streakReminderId = 2;

  static const String _prefEnabled = 'notif_daily_enabled';
  static const String _prefHour = 'notif_daily_hour';
  static const String _prefMinute = 'notif_daily_minute';

  static const TimeOfDay defaultReminderTime = TimeOfDay(hour: 9, minute: 0);

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
        channelDescription: 'Warns you before today\'s puzzle closes',
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

  /// Replaces the OS-facing plugin calls in tests.
  @visibleForTesting
  static NotificationBackend? backendOverride;

  /// Replaces the device time zone in tests.
  @visibleForTesting
  static tz.Location? locationOverride;

  static NotificationBackend get _backend =>
      backendOverride ?? _PluginBackend(_plugin);

  /// Replaces the clock in tests.
  @visibleForTesting
  static DateTime Function()? clockOverride;

  static tz.Location get _location => locationOverride ?? tz.local;

  static bool _initialized = false;
  static bool _timezoneReady = false;

  static bool get isInitialized => _initialized;

  /// Optional callback invoked when the user taps a notification. Payload is
  /// `daily` or `streak`; the router can navigate to `/`.
  static void Function(String? payload)? onNotificationTap;

  /// If the app was cold-started by tapping one of its notifications, passes
  /// that notification's payload to [onNotificationTap]. Never throws.
  static Future<void> handleLaunchFromNotification() async {
    try {
      final payload = await _backend.launchPayloadFromNotification();
      if (payload != null) onNotificationTap?.call(payload);
    } catch (e) {
      AppLogger.debug('Reading notification launch details failed', error: e);
    }
  }

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
      await refreshDailyReminder();
    } catch (e, st) {
      AppLogger.warn('Re-scheduling daily reminder failed', error: e, st: st);
    }

    await _initFcm();
  }

  static Future<void> _ensureTimezone() async {
    if (_timezoneReady || locationOverride != null) return;
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
      AppLogger.info(
        'Subscribed to FCM topic',
        data: {'topic': dailyPuzzleTopic},
      );
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
        final ios = _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >();
        granted =
            await ios?.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            ) ??
            false;
      } else if (!kIsWeb && Platform.isAndroid) {
        final android = _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        granted = await android?.requestNotificationsPermission() ?? true;
      }
    } catch (e, st) {
      AppLogger.warn(
        'Notification permission request failed',
        error: e,
        st: st,
      );
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

  /// True only when the in-app notification setting is on AND the OS lets
  /// the app notify. The one gate every scheduling path goes through.
  static Future<bool> _mayNotify() async {
    try {
      return await isEnabled() && await _backend.hasPermission();
    } catch (e) {
      AppLogger.debug('Notification gate check failed', error: e);
      return false;
    }
  }

  /// Cancels every pending reminder if reminders are no longer allowed (the
  /// player turned them off, or revoked OS permission). Call on app resume so
  /// a revoked permission does not leave scheduled notifications behind until
  /// Home next reloads. Does nothing when reminders are allowed.
  static Future<void> cancelPendingIfNotAllowed() async {
    if (await _mayNotify()) return;
    await _cancelPending(dailyReminderId);
    await _cancelPending(streakReminderId);
  }

  /// Re-arms the daily reminder when allowed (setting on + OS permission),
  /// otherwise cancels any pending one.
  static Future<void> refreshDailyReminder() async {
    if (!await _mayNotify()) {
      await _cancelPending(dailyReminderId);
      return;
    }
    await _scheduleDaily(await reminderTime());
  }

  /// Turns the daily reminder on at [time] (device local time) and persists
  /// the preference. If the OS has notifications off, nothing is scheduled
  /// and the preference stays off.
  static Future<void> scheduleDailyReminder(TimeOfDay time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefHour, time.hour);
    await prefs.setInt(_prefMinute, time.minute);
    await prefs.setBool(_prefEnabled, true);
    if (!await _mayNotify()) {
      await prefs.setBool(_prefEnabled, false);
      await _cancelPending(dailyReminderId);
      return;
    }
    await _scheduleDaily(time);
  }

  static Future<void> _scheduleDaily(TimeOfDay time) async {
    await _ensureTimezone();
    try {
      await _backend.cancel(dailyReminderId);
      await _backend.schedule(
        id: dailyReminderId,
        title: 'Today\'s Icos is ready',
        body: 'A fresh path awaits. Keep your streak alive!',
        at: nextInstanceOf(time, now: tz.TZDateTime.now(_location)),
        android: _androidDaily,
        repeatsDaily: true,
        payload: 'daily',
      );
      AppLogger.info(
        'Daily reminder scheduled',
        data: {'hour': time.hour, 'minute': time.minute},
      );
    } catch (e, st) {
      AppLogger.warn('Scheduling daily reminder failed', error: e, st: st);
    }
  }

  /// Cancels the daily reminder and persists the preference as disabled.
  static Future<void> cancelReminder() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefEnabled, false);
    await _cancelPending(dailyReminderId);
  }

  static Future<void> _cancelPending(int id) async {
    try {
      await _backend.cancel(id);
    } catch (e) {
      AppLogger.debug('Cancelling notification $id failed', error: e);
    }
  }

  // ─── Streak at risk ─────────────────────────────────────────────────

  /// Brings the streak reminder in line with the current state.
  ///
  /// Schedules it only when reminders are allowed (see [_mayNotify]) and the
  /// player has a streak of at least 1. While today's UTC puzzle is unsolved
  /// it targets today's fire time ([streakReminderFireTime]) if still ahead;
  /// once solved ([solvedToday]) it targets tomorrow's, so a player who does
  /// not open the app tomorrow is still warned. In every other case any
  /// pending streak reminder is cancelled. A null [currentStreak] means the
  /// streak is not known yet: nothing is scheduled, but an opt-out still
  /// cancels.
  static Future<void> refreshStreakReminder({
    required bool solvedToday,
    required int? currentStreak,
    DateTime? nowUtc,
  }) async {
    if (!await _mayNotify()) {
      await _cancelPending(streakReminderId);
      return;
    }
    if (currentStreak == null) return;
    if (currentStreak < 1) {
      await _cancelPending(streakReminderId);
      return;
    }

    await _ensureTimezone();
    final now = (nowUtc ?? clockOverride?.call() ?? DateTime.now()).toUtc();
    // Solved today: aim at tomorrow's UTC day, as seen from its first moment.
    final dayStart = solvedToday ? streakDeadlineUtc(now) : now;
    final at = streakReminderFireTime(nowUtc: dayStart, location: _location);
    if (at == null) {
      await _cancelPending(streakReminderId);
      return;
    }
    final hours = streakReminderHoursLeft(at, streakDeadlineUtc(dayStart));

    try {
      await _backend.cancel(streakReminderId);
      await _backend.schedule(
        id: streakReminderId,
        title: 'Keep your streak alive',
        body: streakReminderBody(hours),
        at: at,
        android: _androidStreak,
        repeatsDaily: false,
        payload: 'streak',
      );
    } catch (e, st) {
      AppLogger.warn('Scheduling streak reminder failed', error: e, st: st);
    }
  }

  static Future<void> cancelStreakReminder() =>
      _cancelPending(streakReminderId);

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

/// The OS-facing operations [NotificationService] needs, so the scheduling
/// rules can be tested without a device.
abstract interface class NotificationBackend {
  /// Whether the OS currently lets the app show notifications.
  Future<bool> hasPermission();

  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime at,
    required AndroidNotificationDetails android,
    required bool repeatsDaily,
    required String payload,
  });

  Future<void> cancel(int id);

  /// Payload of the notification whose tap launched the app, or `null` when
  /// the app was not launched from a notification.
  Future<String?> launchPayloadFromNotification();
}

class _PluginBackend implements NotificationBackend {
  const _PluginBackend(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;

  @override
  Future<bool> hasPermission() async {
    if (kIsWeb) return true;
    if (Platform.isIOS) {
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      final options = await ios?.checkPermissions();
      return options?.isEnabled ?? false;
    }
    if (Platform.isAndroid) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      return await android?.areNotificationsEnabled() ?? true;
    }
    return true;
  }

  @override
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime at,
    required AndroidNotificationDetails android,
    required bool repeatsDaily,
    required String payload,
  }) => _plugin.zonedSchedule(
    id: id,
    title: title,
    body: body,
    scheduledDate: at,
    notificationDetails: NotificationDetails(
      android: android,
      iOS: NotificationService._darwin,
    ),
    androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    matchDateTimeComponents: repeatsDaily ? DateTimeComponents.time : null,
    payload: payload,
  );

  @override
  Future<void> cancel(int id) => _plugin.cancel(id: id);

  @override
  Future<String?> launchPayloadFromNotification() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details == null || !details.didNotificationLaunchApp) return null;
    return details.notificationResponse?.payload;
  }
}
