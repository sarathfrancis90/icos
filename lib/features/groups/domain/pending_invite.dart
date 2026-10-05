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
}
