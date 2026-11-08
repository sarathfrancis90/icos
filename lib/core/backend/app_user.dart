import 'package:flutter/foundation.dart';

/// The signed-in Better Auth user.
///
/// [email] is null for anonymous users (Better Auth gives guests a
/// placeholder address that must never be shown). [providers] lists linked
/// sign-in methods: `email`, `google`, `apple` (empty for a guest).
@immutable
class AppUser {
  const AppUser({
    required this.id,
    this.email,
    this.emailVerified = false,
    this.isAnonymous = false,
    this.providers = const [],
    this.name,
    this.createdAt,
  });

  /// Parses a Better Auth user object (`id, email, emailVerified, name,
  /// isAnonymous, createdAt, image`).
  factory AppUser.fromJson(
    Map<String, dynamic> json, {
    List<String>? providers,
  }) {
    final isAnonymous = json['isAnonymous'] == true;
    final email = json['email'];
    final name = json['name'];
    final created = json['createdAt'];
    final storedProviders = json['providers'];
    return AppUser(
      id: json['id'].toString(),
      email: isAnonymous || email is! String || email.isEmpty ? null : email,
      emailVerified: json['emailVerified'] == true,
      isAnonymous: isAnonymous,
      providers:
          providers ??
          (storedProviders is List
              ? storedProviders.whereType<String>().toList()
              : const []),
      name: name is String && name.isNotEmpty ? name : null,
      createdAt: created is String ? DateTime.tryParse(created) : null,
    );
  }

  final String id;
  final String? email;
  final bool emailVerified;
  final bool isAnonymous;
  final List<String> providers;
  final String? name;
  final DateTime? createdAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'emailVerified': emailVerified,
    'isAnonymous': isAnonymous,
    'providers': providers,
    'name': name,
    'createdAt': createdAt?.toIso8601String(),
  };

  AppUser copyWith({List<String>? providers}) => AppUser(
    id: id,
    email: email,
    emailVerified: emailVerified,
    isAnonymous: isAnonymous,
    providers: providers ?? this.providers,
    name: name,
    createdAt: createdAt,
  );

  @override
  bool operator ==(Object other) =>
      other is AppUser &&
      other.id == id &&
      other.email == email &&
      other.emailVerified == emailVerified &&
      other.isAnonymous == isAnonymous &&
      listEquals(other.providers, providers) &&
      other.name == name &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(
    id,
    email,
    emailVerified,
    isAnonymous,
    Object.hashAll(providers),
    name,
    createdAt,
  );
}
