import '../../../core/constants/app_sizes.dart';

/// Helpers for group invite codes.
///
/// Invite codes are generated server-side (6 uppercase alphanumeric
/// characters). The client only normalises and validates user input.
abstract final class InviteCode {
  static final RegExp _pattern =
      RegExp('^[A-Z0-9]{${AppSizes.inviteCodeLength}}\$');

  /// Public deep-link base used in share text and QR codes.
  static const String joinBaseUrl = 'https://icos.sarathfrancis.work/join';

  /// Trims, strips whitespace/dashes and upper-cases the raw input so that
  /// "ab-c 12d" becomes "ABC12D".
  static String normalize(String raw) {
    return raw.replaceAll(RegExp(r'[\s\-]'), '').trim().toUpperCase();
  }

  /// True when [code] (after [normalize]) is exactly six uppercase
  /// alphanumeric characters.
  static bool isValid(String code) => _pattern.hasMatch(normalize(code));

  /// Returns a user-facing validation message, or `null` when valid.
  static String? validate(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return 'Please enter an invite code';
    }
    if (!isValid(raw)) {
      return 'Enter a ${AppSizes.inviteCodeLength}-character code '
          '(letters and numbers)';
    }
    return null;
  }

  /// Builds the shareable deep link for [code].
  static String joinLink(String code) => '$joinBaseUrl/${normalize(code)}';
}
