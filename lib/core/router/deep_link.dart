import '../services/app_config_provider.dart';

/// Deep-link locations that may be resumed after onboarding.
final RegExp _joinLink = RegExp(r'^/join/[A-Za-z0-9]{6}$');
final RegExp _puzzleLink = RegExp(r'^/puzzle/\d{4}-\d{2}-\d{2}$');

/// Returns [raw] when it is a known deep-link location
/// (`/join/<6 alphanumerics>` or `/puzzle/<yyyy-mm-dd>`), otherwise `null`.
/// Query strings and fragments are dropped so only the path is honoured.
String? sanitizeDeepLink(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final uri = Uri.tryParse(raw);
  if (uri == null || uri.hasScheme || uri.hasAuthority) return null;
  final path = uri.path;
  if (_joinLink.hasMatch(path) || _puzzleLink.hasMatch(path)) return path;
  return null;
}

/// Returns [raw] only when it is `/join/<6 alphanumerics>`. Used for the
/// invite carried through account creation, where nothing else qualifies
/// (unlike [sanitizeDeepLink], which onboarding uses and which also allows
/// puzzle links).
String? sanitizeJoinLink(String? raw) {
  final path = sanitizeDeepLink(raw);
  return path != null && _joinLink.hasMatch(path) ? path : null;
}

/// The location to send a first-time user to, preserving a requested deep
/// link through onboarding. Returns `null` when no redirect is needed.
String? onboardingRedirect({
  required Uri uri,
  required bool hasSeenOnboarding,
}) {
  if (hasSeenOnboarding || uri.path == '/onboarding') return null;
  final from = sanitizeDeepLink(uri.path);
  if (from == null) return '/onboarding';
  return Uri(path: '/onboarding', queryParameters: {'from': from}).toString();
}

/// Where a player whose password-recovery link just signed them in sets a
/// new password.
const String kNewPasswordPath = '/auth/new-password';

/// Sends the player to the "set a new password" screen while a recovery is
/// pending, and away from it once it is not. `null` = no redirect.
String? recoveryRedirect({required String path, required bool pending}) {
  if (pending && path != kNewPasswordPath) return kNewPasswordPath;
  if (!pending && path == kNewPasswordPath) return '/';
  return null;
}

/// Where a signed-in player whose account has a pending deletion is held.
const String kDeletionPendingPath = '/account-deletion';

/// Blocks the app while a deletion is pending and releases it once it is not.
String? deletionRedirect({required String path, required bool pending}) {
  if (pending && path != kDeletionPendingPath) return kDeletionPendingPath;
  if (!pending && path == kDeletionPendingPath) return '/';
  return null;
}

/// The single app-level redirect. Gates are checked in priority order
/// (maintenance, force update, banned, pending deletion, password recovery,
/// onboarding) and every active gate is terminal: it either holds the player
/// on its own screen (`null`) or sends them there, so a lower gate can never
/// bounce them away and cause a redirect loop.
String? appRedirect({
  required Uri uri,
  required AppGate gate,
  required bool banned,
  required bool pendingDeletion,
  required bool recoveryPending,
  required bool hasSeenOnboarding,
}) {
  final path = uri.path;
  if (gate == AppGate.maintenance) {
    return path == '/maintenance' ? null : '/maintenance';
  }
  if (gate == AppGate.forceUpdate) {
    return path == '/force-update' ? null : '/force-update';
  }
  if (path == '/maintenance' || path == '/force-update') return '/';
  if (banned) return path == '/banned' ? null : '/banned';
  if (path == '/banned') return '/';
  if (pendingDeletion) {
    return deletionRedirect(path: path, pending: true);
  }
  if (path == kDeletionPendingPath) return '/';
  if (recoveryPending) {
    return recoveryRedirect(path: path, pending: true);
  }
  if (path == kNewPasswordPath) return '/';
  return onboardingRedirect(uri: uri, hasSeenOnboarding: hasSeenOnboarding);
}
