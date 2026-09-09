import '../../../core/constants/app_sizes.dart';
import '../../../core/moderation/banned_words.dart';
import '../../../core/utils/text_sanitizer.dart' as shared;

/// Validation for group names (client-side pre-check; the `create_group`
/// RPC re-validates and sanitises server-side).
///
/// Rules: 2–[AppSizes.maxGroupNameLength] visible characters after
/// sanitisation, no control / zero-width characters, no profanity.
///
/// Delegates Unicode sanitisation and the word list to the shared
/// `text_sanitizer` / [ProfanityFilter]; the small local list below is an
/// extra guard for reserved/impersonation terms.
abstract final class GroupNameValidator {
  static const int minLength = 2;
  static const int maxLength = AppSizes.maxGroupNameLength;

  /// Reserved / impersonation terms blocked in addition to the shared
  /// profanity list.
  static const List<String> _blockedWords = [
    'admin',
    'moderator',
    'icos',
    'support',
  ];

  static final RegExp _invisible = RegExp(
    r'[\u0000-\u001F\u007F-\u009F\u200B-\u200F\u202A-\u202E\u2060-\u206F\uFEFF]',
  );
  static final RegExp _combining = RegExp(r'[\u0300-\u036F]{3,}');
  static final RegExp _whitespace = RegExp(r'\s+');

  /// Strips invisible/control characters, collapses whitespace and removes
  /// zalgo-style stacked combining marks.
  static String sanitize(String raw) {
    // Generous clamp so the length check below can still report "too long".
    final cleaned = shared.sanitizeText(raw, maxLength: 512);
    return cleaned
        .replaceAll(_invisible, '')
        .replaceAll(_combining, '')
        .replaceAll(_whitespace, ' ')
        .trim();
  }

  /// Returns a user-facing error, or `null` when [raw] is acceptable.
  static String? validate(String? raw) {
    if (raw == null) return 'Please enter a group name';
    final name = sanitize(raw);
    if (name.isEmpty) return 'Please enter a group name';
    if (name.runes.length < minLength) {
      return 'Must be at least $minLength characters';
    }
    if (name.runes.length > maxLength) {
      return 'Max $maxLength characters';
    }
    if (containsProfanity(name)) {
      return 'This name is not allowed';
    }
    return null;
  }

  /// True when [text] contains profanity (shared filter) or a reserved term
  /// (case-insensitive, with common leetspeak substitutions collapsed).
  static bool containsProfanity(String text) {
    if (ProfanityFilter.containsProfanity(text) ||
        ProfanityFilter.containsReservedWord(text)) {
      return true;
    }
    final normalized = text
        .toLowerCase()
        .replaceAll('0', 'o')
        .replaceAll('1', 'i')
        .replaceAll('3', 'e')
        .replaceAll('4', 'a')
        .replaceAll('5', 's')
        .replaceAll('7', 't')
        .replaceAll('@', 'a')
        .replaceAll(r'$', 's')
        .replaceAll(RegExp(r'[^a-z]'), '');
    for (final word in _blockedWords) {
      if (normalized.contains(word)) return true;
    }
    return false;
  }
}
