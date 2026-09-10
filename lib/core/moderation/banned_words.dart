/// Shared profanity / slur filter used for display names and group names.
///
/// Matching strategy:
/// 1. Lower-case the input and apply leetspeak normalisation
///    (`4`→`a`, `3`→`e`, `1`/`!`→`i`, `0`→`o`, `$`/`5`→`s`, `7`→`t`, `@`→`a`).
/// 2. Collapse repeated characters (`shiiit` → `shit`) for a second pass.
/// 3. [bannedSubstrings] (the worst slurs) match anywhere in the string.
/// 4. [bannedWords] match on whole words only, so "Scunthorpe" and
///    "assistant" are not false positives.
abstract final class ProfanityFilter {
  /// Terms that are blocked when they appear as a whole word.
  static const List<String> bannedWords = [
    'anal',
    'anus',
    'arse',
    'arsehole',
    'ass',
    'asshole',
    'ballsack',
    'bastard',
    'bitch',
    'bitches',
    'blowjob',
    'bollocks',
    'boner',
    'boob',
    'boobs',
    'bugger',
    'bullshit',
    'clit',
    'cock',
    'cocks',
    'cocksucker',
    'coon',
    'cum',
    'cunt',
    'cunts',
    'dick',
    'dickhead',
    'dildo',
    'douche',
    'douchebag',
    'dyke',
    'fag',
    'fags',
    'fuck',
    'fucked',
    'fucker',
    'fucking',
    'fucks',
    'goddamn',
    'handjob',
    'homo',
    'jackass',
    'jerkoff',
    'jizz',
    'motherfucker',
    'nazi',
    'nutsack',
    'paki',
    'penis',
    'piss',
    'pissed',
    'porn',
    'prick',
    'pussy',
    'queef',
    'rape',
    'rapist',
    'retard',
    'retarded',
    'scrotum',
    'sex',
    'shit',
    'shite',
    'shithead',
    'shitty',
    'slut',
    'sluts',
    'smegma',
    'spic',
    'tit',
    'tits',
    'titties',
    'twat',
    'vagina',
    'wank',
    'wanker',
    'whore',
    'whores',
  ];

  /// The most severe slurs; blocked even when embedded inside other text.
  static const List<String> bannedSubstrings = [
    'nigger',
    'nigga',
    'niggr',
    'faggot',
    'fagot',
    'chink',
    'kike',
    'wetback',
    'tranny',
    'raghead',
    'towelhead',
    'beaner',
    'gook',
    'spook',
    'hitler',
  ];

  /// Reserved / impersonation terms that are not profanity but should never
  /// be usable as a display name.
  static const List<String> reservedWords = [
    'admin',
    'administrator',
    'moderator',
    'mod',
    'icos',
    'support',
    'official',
    'staff',
  ];

  /// Leetspeak → letter map applied before matching.
  static const Map<String, String> leetMap = {
    '4': 'a',
    '@': 'a',
    '8': 'b',
    '3': 'e',
    '€': 'e',
    '1': 'i',
    '!': 'i',
    '|': 'i',
    '0': 'o',
    r'$': 's',
    '5': 's',
    '7': 't',
    '+': 't',
    '2': 'z',
  };

  static final RegExp _nonLetter = RegExp('[^a-z]+');
  static final RegExp _repeats = RegExp(r'(.)\1+');

  /// Applies [leetMap] to a lower-cased string.
  static String normalizeLeet(String input) {
    final buffer = StringBuffer();
    for (final rune in input.toLowerCase().runes) {
      final ch = String.fromCharCode(rune);
      buffer.write(leetMap[ch] ?? ch);
    }
    return buffer.toString();
  }

  /// Produces the candidate strings that are checked against the lists:
  /// leet-normalised text, and the same with repeated letters collapsed.
  static List<String> _candidates(String input) {
    final normalized = normalizeLeet(input);
    final collapsed = normalized.replaceAllMapped(_repeats, (m) => m[1]!);
    return collapsed == normalized ? [normalized] : [normalized, collapsed];
  }

  static List<String> _words(String normalized) => normalized
      .split(_nonLetter)
      .where((w) => w.isNotEmpty)
      .toList(growable: false);

  /// Whether [input] contains profanity or a slur.
  static bool containsProfanity(String input) {
    if (input.isEmpty) return false;
    for (final candidate in _candidates(input)) {
      // Embedded slurs — also check with separators removed so that
      // "n.i.g.g.e.r" is caught.
      final squashed = candidate.replaceAll(_nonLetter, '');
      for (final slur in bannedSubstrings) {
        if (candidate.contains(slur) || squashed.contains(slur)) return true;
      }
      final words = _words(candidate);
      for (final word in words) {
        if (bannedWords.contains(word)) return true;
      }
      // Whole-word check on the squashed form catches "f u c k".
      if (words.length > 1 && bannedWords.contains(squashed)) return true;
    }
    return false;
  }

  /// Whether [input] contains a reserved / impersonation term.
  static bool containsReservedWord(String input) {
    if (input.isEmpty) return false;
    final normalized = normalizeLeet(input);
    final words = _words(normalized);
    for (final word in words) {
      if (reservedWords.contains(word)) return true;
    }
    // Names that *start* with the brand (e.g. "icosbot", "icos official")
    // impersonate us; a substring match would wrongly block "Nicos".
    return normalized.startsWith('icos');
  }

  /// True when the text is blocked for any reason (profanity or reserved).
  static bool isBlocked(String input) =>
      containsProfanity(input) || containsReservedWord(input);
}
