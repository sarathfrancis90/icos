import '../moderation/banned_words.dart';

export '../moderation/banned_words.dart' show ProfanityFilter;

/// Maximum length (in Unicode code points) of a display name after
/// sanitising.
const int kMaxDisplayNameLength = 30;

/// Minimum length of a display name after sanitising.
const int kMinDisplayNameLength = 2;

/// Maximum length of a group name after sanitising.
const int kMaxGroupNameLength = 30;

/// Error message shown when a name is rejected by the profanity filter.
const String kNameNotAllowedMessage = 'Please choose a different name';

/// Pure-Dart text sanitiser for user-supplied names.
///
/// Performs an NFKC-ish normalisation without any dependencies:
/// - full-width ASCII (U+FF01..U+FF5E) is folded to ASCII,
/// - zero-width / invisible characters (U+200B..U+200F, U+2060..U+2064,
///   U+FEFF, U+00AD, U+180E) are removed,
/// - C0/C1 control characters and Unicode line/paragraph separators are
///   removed,
/// - bidi override / isolate controls (U+202A..U+202E, U+2066..U+2069) are
///   removed,
/// - runs of more than two consecutive combining marks ("zalgo") are
///   truncated to two,
/// - whitespace is collapsed to a single space and trimmed,
/// - the result is clamped to [maxLength] code points.
String sanitizeText(String input, {int maxLength = kMaxDisplayNameLength}) {
  final out = StringBuffer();
  var combiningRun = 0;
  var lastWasSpace = false;

  for (final rune in input.runes) {
    var cp = rune;

    // Full-width ASCII variants -> ASCII.
    if (cp >= 0xFF01 && cp <= 0xFF5E) {
      cp = cp - 0xFF01 + 0x21;
    }
    // Ideographic space -> regular space.
    if (cp == 0x3000) cp = 0x20;

    if (_isInvisible(cp) || _isControl(cp)) continue;

    if (_isCombiningMark(cp)) {
      combiningRun++;
      if (combiningRun > 2) continue;
      out.writeCharCode(cp);
      continue;
    }
    combiningRun = 0;

    if (_isWhitespace(cp)) {
      if (lastWasSpace || out.isEmpty) continue; // collapse + leading trim
      lastWasSpace = true;
      out.writeCharCode(0x20);
      continue;
    }
    lastWasSpace = false;
    out.writeCharCode(cp);
  }

  var result = out.toString();
  if (result.endsWith(' ')) result = result.trimRight();

  // Clamp by code points (not UTF-16 units) so surrogate pairs stay intact.
  final runes = result.runes.toList(growable: false);
  if (runes.length > maxLength) {
    result = String.fromCharCodes(runes.take(maxLength)).trimRight();
  }
  return result;
}

/// Sanitises a display name (see [sanitizeText]) and clamps to
/// [kMaxDisplayNameLength].
String sanitizeDisplayName(String input) =>
    sanitizeText(input, maxLength: kMaxDisplayNameLength);

/// Validates a display name. Returns an error message, or `null` when valid.
///
/// Rules: 2..30 code points after sanitising; no profanity; no reserved
/// impersonation terms.
String? validateName(String input) {
  final clean = sanitizeDisplayName(input);
  final length = clean.runes.length;
  if (length == 0) return 'Display name cannot be empty';
  if (length < kMinDisplayNameLength) {
    return 'Must be at least $kMinDisplayNameLength characters';
  }
  if (length > kMaxDisplayNameLength) {
    return 'Max $kMaxDisplayNameLength characters';
  }
  if (ProfanityFilter.containsProfanity(clean)) return kNameNotAllowedMessage;
  if (ProfanityFilter.containsReservedWord(clean)) {
    return 'This name is reserved';
  }
  return null;
}

/// Validates a group name. Returns an error message, or `null` when valid.
String? validateGroupName(String input) {
  final clean = sanitizeText(input, maxLength: kMaxGroupNameLength);
  final length = clean.runes.length;
  if (length == 0) return 'Group name cannot be empty';
  if (length < kMinDisplayNameLength) {
    return 'Must be at least $kMinDisplayNameLength characters';
  }
  if (ProfanityFilter.containsProfanity(clean)) return kNameNotAllowedMessage;
  return null;
}

bool _isInvisible(int cp) =>
    (cp >= 0x200B && cp <= 0x200F) ||
    (cp >= 0x2060 && cp <= 0x2064) ||
    (cp >= 0x202A && cp <= 0x202E) ||
    (cp >= 0x2066 && cp <= 0x2069) ||
    cp == 0xFEFF ||
    cp == 0x00AD ||
    cp == 0x180E ||
    cp == 0x034F || // combining grapheme joiner
    (cp >= 0xFE00 && cp <= 0xFE0F); // variation selectors

bool _isControl(int cp) =>
    (cp < 0x20 && !_isWhitespace(cp)) ||
    (cp >= 0x7F && cp <= 0x9F) ||
    cp == 0x2028 ||
    cp == 0x2029;

bool _isWhitespace(int cp) =>
    cp == 0x20 ||
    cp == 0x09 ||
    cp == 0x0A ||
    cp == 0x0B ||
    cp == 0x0C ||
    cp == 0x0D ||
    cp == 0x85 ||
    cp == 0xA0 ||
    cp == 0x1680 ||
    (cp >= 0x2000 && cp <= 0x200A) ||
    cp == 0x202F ||
    cp == 0x205F ||
    cp == 0x3000;

bool _isCombiningMark(int cp) =>
    (cp >= 0x0300 && cp <= 0x036F) ||
    (cp >= 0x0483 && cp <= 0x0489) ||
    (cp >= 0x0591 && cp <= 0x05BD) ||
    (cp >= 0x0610 && cp <= 0x061A) ||
    (cp >= 0x064B && cp <= 0x065F) ||
    (cp >= 0x1AB0 && cp <= 0x1AFF) ||
    (cp >= 0x1DC0 && cp <= 0x1DFF) ||
    (cp >= 0x20D0 && cp <= 0x20FF) ||
    (cp >= 0xFE20 && cp <= 0xFE2F);
