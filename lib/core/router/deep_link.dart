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
