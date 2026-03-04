import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';

part 'auth_provider.g.dart';

@riverpod
class AuthNotifier extends _$AuthNotifier {
  @override
  AsyncValue<User?> build() {
    final user = SupabaseService.auth.currentUser;
    _listenAuthChanges();
    return AsyncValue.data(user);
  }

  void _listenAuthChanges() {
    SupabaseService.auth.onAuthStateChange.listen((data) {
      state = AsyncValue.data(data.session?.user);
    });
  }

  Future<void> signInAnonymously() async {
    state = const AsyncValue.loading();
    try {
      await SupabaseService.auth.signInAnonymously();
      state = AsyncValue.data(SupabaseService.auth.currentUser);
    } on AuthException catch (e) {
      state = AsyncValue.error(e.message, StackTrace.current);
    }
  }

  Future<void> signInWithGoogle() async {
    state = const AsyncValue.loading();
    try {
      await SupabaseService.auth.signInWithOAuth(OAuthProvider.google);
      state = AsyncValue.data(SupabaseService.auth.currentUser);
    } on AuthException catch (e) {
      state = AsyncValue.error(e.message, StackTrace.current);
    }
  }

  Future<void> signInWithApple() async {
    state = const AsyncValue.loading();
    try {
      await SupabaseService.auth.signInWithOAuth(OAuthProvider.apple);
      state = AsyncValue.data(SupabaseService.auth.currentUser);
    } on AuthException catch (e) {
      state = AsyncValue.error(e.message, StackTrace.current);
    }
  }

  Future<void> signUpWithEmail(String email, String password) async {
    state = const AsyncValue.loading();
    try {
      final response = await SupabaseService.auth.signUp(
        email: email,
        password: password,
      );
      state = AsyncValue.data(response.user);
    } on AuthException catch (e) {
      state = AsyncValue.error(e.message, StackTrace.current);
      throw Exception(e.message);
    }
  }

  Future<void> signInWithEmail(String email, String password) async {
    state = const AsyncValue.loading();
    try {
      final response = await SupabaseService.auth.signInWithPassword(
        email: email,
        password: password,
      );
      state = AsyncValue.data(response.user);
    } on AuthException catch (e) {
      state = AsyncValue.error(e.message, StackTrace.current);
      throw Exception(e.message);
    }
  }

  Future<void> signOut() async {
    await SupabaseService.auth.signOut();
    state = const AsyncValue.data(null);
  }

  bool get isAuthenticated =>
      SupabaseService.auth.currentUser != null;

  bool get isAnonymous =>
      SupabaseService.auth.currentUser?.isAnonymous ?? true;
}

@riverpod
Stream<AuthState> authStateChanges(Ref ref) {
  return SupabaseService.auth.onAuthStateChange;
}
