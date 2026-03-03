abstract final class AppDateUtils {
  static String todayUtc() {
    final now = DateTime.now().toUtc();
    return formatDate(now);
  }

  static String formatDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static DateTime parseDate(String dateStr) {
    return DateTime.parse(dateStr);
  }

  static String tomorrowUtc() {
    final tomorrow = DateTime.now().toUtc().add(const Duration(days: 1));
    return formatDate(tomorrow);
  }

  /// Returns the day of week (1 = Monday, 7 = Sunday) for difficulty scaling.
  static int dayOfWeek() {
    return DateTime.now().toUtc().weekday;
  }

  /// Returns Monday 00:00 UTC of the current week.
  static DateTime weekStart() {
    final now = DateTime.now().toUtc();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    return DateTime.utc(monday.year, monday.month, monday.day);
  }

  /// Format seconds into mm:ss display.
  static String formatTime(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// Format seconds into a human-readable string.
  static String formatTimeHuman(int totalSeconds) {
    if (totalSeconds < 60) {
      return '${totalSeconds}s';
    }
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    if (seconds == 0) {
      return '${minutes}m';
    }
    return '${minutes}m ${seconds}s';
  }
}
