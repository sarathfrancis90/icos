abstract final class AppStrings {
  static const appName = 'Icos';
  static const appTagline = 'One line. Every cell.';

  // Navigation
  static const navHome = 'Home';
  static const navGroups = 'Groups';
  static const navStats = 'Stats';
  static const navProfile = 'Profile';

  // Puzzle
  static const puzzleTitle = "Today's Puzzle";
  static const puzzleSolvedTitle = 'Puzzle Complete!';
  static const puzzleHint = 'Hint';
  static const puzzleUndo = 'Undo';
  static const puzzleReset = 'Reset';
  static const puzzleTimer = 'Time';
  static const puzzlePar = 'Par';
  static const offlinePuzzleNotice =
      "Offline puzzle. This one is just for practice and won't count toward "
      'your streak.';

  // Password recovery
  static const forgotPassword = 'Forgot password?';
  static const resetPasswordTitle = 'Reset your password';
  static const resetPasswordPrompt =
      "Enter your email and we'll send you a link to reset your password.";
  static const resetLinkSent =
      "If an account exists for that email, we've sent a link to reset your "
      'password.';
  static const resetSendLink = 'Send link';
  static const resetRateLimited =
      'Too many reset requests. Please try again in a little while.';
  static const close = 'Close';
  static const cancel = 'Cancel';
  static const emailLabel = 'Email';
  static const emailRequired = 'Email is required';
  static const emailInvalid = 'Enter a valid email address';
  static const passwordHint = 'At least 6 characters';
  static const showPassword = 'Show password';
  static const hidePassword = 'Hide password';
  static const notNow = 'Not now';
  static const recoveryExpired =
      'This reset link has expired. Request a new one to set a new password.';
  static const requestNewLink = 'Send a new link';
  static const recoveryGuestWarning =
      "You're signing in to an existing account. Progress from the guest "
      "profile on this device won't carry over.";
  static const newPasswordTitle = 'Set a new password';
  static const newPasswordSubtitle = 'Choose a new password for your account.';
  static const newPasswordLabel = 'New password';
  static const confirmPasswordLabel = 'Confirm password';
  static const savePassword = 'Save password';
  static const passwordUpdated = 'Password updated.';
  static const passwordRequired = 'Password is required';
  static const passwordTooShort = 'Password must be at least 6 characters';
  static const passwordsDoNotMatch = 'Passwords do not match';

  // Account deletion (blocking screen)
  static const deletionPendingTitle = 'Account scheduled for deletion';
  static const signOut = 'Sign out';

  // Stats
  static const statsShowingSaved = 'Showing saved stats';
  static const statsLoadFailed = 'Failed to load stats. Pull down to retry.';

  // Difficulty
  static const difficultyEasy = 'Easy';
  static const difficultyMedium = 'Medium';
  static const difficultyHard = 'Hard';
  static const difficultyExpert = 'Expert';

  // Auth
  static const signIn = 'Sign In';
  static const signUp = 'Create Account';
  static const signInWithGoogle = 'Continue with Google';
  static const signInWithApple = 'Continue with Apple';
  static const signInWithEmail = 'Continue with Email';
  static const signUpWithEmail = 'Sign up with Email';
  static const alreadyHaveAccount = 'Already have an account? Sign in';
  static const continueAsGuest = 'Continue as Guest';
  static const linkAccountPrompt =
      'Create an account to save your progress and join groups';

  // Groups
  static const createGroup = 'Create Group';
  static const joinGroup = 'Join Group';
  static const groupInviteCode = 'Invite Code';
  static const groupLeaderboard = 'Leaderboard';
  static const groupMembers = 'Members';
  static const groupDaily = 'Daily';
  static const groupWeekly = 'Weekly';
  static const leaveGroup = 'Leave Group';
  static const groupNotFound = 'Group not found';
  static const noLeaderboardData = 'No one has played yet';
  static const accountRequired = 'Account Required';
  static const inviteCodeCopied = 'Invite code copied';

  // Blocking
  static const blockUser = 'Block user';
  static const unblockUser = 'Unblock user';
  static const blockedUserName = 'Blocked user';
  static const blockConfirmLabel = 'Block';
  static const blockedUsers = 'Blocked users';
  static const blockedUsersSubtitle = 'Manage people you have blocked';
  static const noBlockedUsers = "You haven't blocked anyone.";
  static const unblockButton = 'Unblock';
  static const retry = 'Retry';
  static const blockedUsersLoadFailed = 'Could not load blocked users.';
  static const blockBody =
      "You won't see their scores or activity in any group. They won't be "
      "told. We'll also be notified so we can review their account.";
  static String blockTitle(String name) => 'Block $name?';
  static String userBlocked(String name) => '$name blocked';
  static String userUnblocked(String name) => '$name unblocked';

  // Stats
  static const currentStreak = 'Current Streak';
  static const longestStreak = 'Longest Streak';
  static const totalSolved = 'Total Solved';
  static const averageTime = 'Avg Time';
  static const streakFreeze = 'Streak Freeze';

  // Share
  static const shareTitle = 'Icos';
  static const shareMessage = 'I solved today\'s Icos in';

  // Errors
  static const errorGeneric = 'Something went wrong. Please try again.';
  static const errorNetwork = 'No internet connection';
  static const errorTimeout = 'Request timed out';
  static const errorPuzzleNotFound = 'Puzzle not available';

  // Accessibility
  static const a11yEmptyCell = 'empty';
  static const a11yFilledCell = 'filled';
  static const a11yWaypointCell = 'waypoint';
  static const a11yWallCell = 'wall';
  static const a11yRow = 'Row';
  static const a11yColumn = 'Column';

  // Legal / support
  static const consentPrefix = 'By continuing, you agree to our ';
  static const consentAnd = ' and ';
  static const termsOfService = 'Terms of Service';
  static const privacyPolicy = 'Privacy Policy';
  static const contactSupport = 'Contact support';
  static const contactSupportSemantics = 'Contact support by email';
  static String couldNotOpen(String url) => 'Could not open $url';
  static String couldNotOpenMail(String email) =>
      'Could not open your mail app. Email $email';
}
