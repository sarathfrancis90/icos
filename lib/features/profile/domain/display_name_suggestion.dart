import 'display_name_placeholder.dart';

const int _maxLength = 30;

/// Name the identity provider gave us, in the same order as
/// `public.provider_display_name` in the database; null when there is none.
String? providerName(Map<String, dynamic>? meta) {
  String? s(String key) {
    final v = meta?[key];
    if (v is! String) return null;
    final t = v.trim();
    return t.isEmpty ? null : t;
  }

  final full = s('full_name') ?? s('name');
  if (full != null) return full;
  final given = s('given_name');
  final family = s('family_name');
  final joined = [?given, ?family].join(' ');
  if (joined.isNotEmpty) return joined;
  return s('preferred_username');
}

/// The local part of [email], tidied like the database does (split on
/// `._-+`, title-case, collapse spaces, cap 30). Null for Apple relay
/// addresses (random by construction), or when nothing usable remains.
String? tidyEmailLocalPart(String? email) {
  if (email == null) return null;
  final at = email.indexOf('@');
  if (at < 1) return null;
  final domain = email.substring(at + 1).toLowerCase();
  if (domain == 'privaterelay.appleid.com') return null;
  final spaced = email.substring(0, at).replaceAll(RegExp(r'[._\-+]+'), ' ');
  final buffer = StringBuffer();
  var startOfWord = true;
  for (final rune in spaced.runes) {
    final ch = String.fromCharCode(rune);
    final isAlnum = RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(ch);
    buffer.write(startOfWord ? ch.toUpperCase() : ch.toLowerCase());
    startOfWord = !isAlnum;
  }
  final tidy = buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  if (tidy.isEmpty) return null;
  return tidy.length > _maxLength ? tidy.substring(0, _maxLength) : tidy;
}

/// Prefill for the "Choose your display name" sheet: the provider's name, else
/// the tidied email local part, else empty.
String suggestDisplayName({
  required Map<String, dynamic>? meta,
  required String? email,
}) {
  final name = providerName(meta) ?? tidyEmailLocalPart(email) ?? '';
  return name.length > _maxLength ? name.substring(0, _maxLength) : name;
}

/// What to prefill given the account's current name: a name the player (or a
/// previous sign-in) already settled on is kept; a placeholder is replaced by
/// the suggestion.
String initialDisplayName({
  required String? currentName,
  required Map<String, dynamic>? meta,
  required String? email,
}) {
  if (currentName != null && !isPlaceholderDisplayName(currentName)) {
    return currentName;
  }
  return suggestDisplayName(meta: meta, email: email);
}
