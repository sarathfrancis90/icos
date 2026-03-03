abstract final class AppSizes {
  // Spacing
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;

  // Grid
  static const double gridPadding = 24;
  static const double gridMaxWidth = 500;
  static const double contentMaxWidth = 600;
  static const int minGridSize = 5;
  static const int maxGridSize = 8;

  // Touch targets (Apple HIG + Material)
  static const double minTouchTarget = 44;

  // Border radius
  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;
  static const double radiusXl = 24;

  // Animation durations (ms)
  static const int themeTransitionMs = 300;
  static const int celebrationTotalMs = 800;
  static const int celebrationRippleMs = 200;
  static const int celebrationConfettiMs = 600;
  static const int pathDrawMs = 150;
  static const int cellFillMs = 100;

  // Limits
  static const int maxGroupMembers = 50;
  static const int inviteCodeLength = 6;
  static const int maxDisplayNameLength = 20;
  static const int maxGroupNameLength = 30;
  static const int hiveCacheLimitMb = 50;
  static const int scoreRateLimitPerHour = 10;

  // Streak
  static const int streakFreezePerWeek = 1;
  static const int accountDeletionGraceDays = 30;
  static const int anonymousPurgeDays = 90;

  // Breakpoints
  static const double tabletBreakpoint = 768;
}
