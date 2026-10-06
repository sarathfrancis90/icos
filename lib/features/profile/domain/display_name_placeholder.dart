/// Whether [name] is one the app assigned because it had nothing better
/// ("Player 1234"), so it is safe to ask the player for a real one.
///
/// Mirrors `public.is_placeholder_display_name` in the database.
bool isPlaceholderDisplayName(String? name) {
  if (name == null || name.trim().isEmpty) return true;
  return _placeholder.hasMatch(name);
}

final RegExp _placeholder = RegExp(r'^Player \d{4}$');
