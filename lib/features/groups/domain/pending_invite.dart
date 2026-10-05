import '../../../core/router/deep_link.dart';
import '../../../core/services/storage_service.dart';

/// The invite a guest was joining when they went off to create an account.
///
/// Creating an account through the browser (OAuth) or an email link replaces
/// the navigation stack, so the invite is kept on the device and resumed when
/// the account is linked or signed in. It is consumed exactly once, expires
/// after [maxAge], and a stored value that is not a valid code is discarded.
abstract final class PendingInvite {
  static const Duration maxAge = Duration(minutes: 30);
  static final RegExp _code = RegExp(r'^[A-Za-z0-9]{6}$');

  /// Remembers [code] (ignored unless it is 6 alphanumerics).
  static Future<void> save(String code, {DateTime? now}) async {
    if (!_code.hasMatch(code)) return;
    try {
      await StorageService.savePendingInvite(
        code.toUpperCase(),
        (now ?? DateTime.now()).millisecondsSinceEpoch,
      );
    } catch (_) {
      // Storage unavailable: the invite just is not resumed.
    }
  }

  static Future<void> clear() async {
    try {
      await StorageService.clearPendingInvite();
    } catch (_) {}
  }

  /// The stored code if it is valid and fresh, otherwise `null`. Always
  /// clears the store, so a second call returns `null`.
  static Future<String?> consume({DateTime? now}) async {
    String? code;
    int? at;
    try {
      code = StorageService.pendingInviteCode;
      at = StorageService.pendingInviteAtMs;
    } catch (_) {
      return null;
    }
    if (code == null && at == null) return null;
    await clear();
    if (code == null || at == null || !_code.hasMatch(code)) return null;
    final age = (now ?? DateTime.now()).difference(
      DateTime.fromMillisecondsSinceEpoch(at),
    );
    if (age.isNegative || age > maxAge) return null;
    return code;
  }

  /// Whether [location] is a screen the stored invite for [code] belongs to:
  /// the join screen for that code, or an auth screen opened from it
  /// (`/auth…?from=/join/<code>`).
  static bool isActiveFor(String code, Uri location) {
    final join = '/join/$code'.toLowerCase();
    if (location.path.toLowerCase() == join) return true;
    final onAuth =
        location.path == '/auth' || location.path.startsWith('/auth/');
    if (!onAuth) return false;
    final from = sanitizeJoinLink(location.queryParameters['from']);
    return from != null && from.toLowerCase() == join;
  }

  /// Drops the stored invite unless [location] is the join screen for it or
  /// an auth screen opened from it. The invite is only meant to bridge the
  /// short detour through sign-up; one left behind (app killed, back at the
  /// root of a cold-start link, `go()` elsewhere) would otherwise send a later
  /// sign-in to a group the player has since walked away from.
  static Future<void> clearUnlessActive(Uri location) async {
    String? code;
    int? at;
    try {
      code = StorageService.pendingInviteCode;
      at = StorageService.pendingInviteAtMs;
    } catch (_) {
      return;
    }
    if (code == null && at == null) return;
    if (code != null && isActiveFor(code, location)) return;
    await clear();
  }
}
