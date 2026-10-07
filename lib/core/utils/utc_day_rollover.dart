import 'dart:async';

import 'date_utils.dart';

/// Notices the 00:00 UTC rollover (a new daily puzzle) while the app stays in
/// the foreground, and on demand (e.g. on resume).
///
/// [start] arms a one-shot timer for the next 00:00:01 UTC that calls
/// [check] and re-arms itself. Timers can be suspended while the app is in
/// the background, so call [check] and [start] again on resume.
class UtcDayRollover {
  UtcDayRollover({required this.onNewDay})
    : _lastKnownDate = AppDateUtils.todayUtc();

  /// Called with the new UTC date (`YYYY-MM-DD`) once per day change.
  final void Function(String today) onNewDay;

  String _lastKnownDate;
  Timer? _timer;

  /// (Re-)arms the timer for the next rollover.
  void start() {
    _timer?.cancel();
    _timer = Timer(AppDateUtils.untilNextRollover(), () {
      check();
      start();
    });
  }

  /// Calls [onNewDay] if the UTC date changed since the last check. Returns
  /// whether it did.
  bool check() {
    final today = AppDateUtils.todayUtc();
    if (today == _lastKnownDate) return false;
    _lastKnownDate = today;
    onNewDay(today);
    return true;
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
