import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_client.dart';

class AuthRepository {
  Future<AuthResponse> signIn({required String email, required String password}) {
    return supabase.auth.signInWithPassword(email: email, password: password);
  }

  /// [name] is stored as `full_name` in user metadata. The dashboard greets
  /// with it, which is why sign-up asks for it at all.
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    String? name,
  }) {
    final trimmed = name?.trim();
    return supabase.auth.signUp(
      email: email,
      password: password,
      data: trimmed == null || trimmed.isEmpty ? null : {'full_name': trimmed},
    );
  }

  Future<void> sendPasswordReset(String email) =>
      supabase.auth.resetPasswordForEmail(email);

  Future<void> signOut() => supabase.auth.signOut();

  User? get currentUser => supabase.auth.currentUser;

  /// The name to greet with: what they typed at sign-up, else the local part
  /// of their email, else nothing.
  String? get displayName {
    final user = currentUser;
    if (user == null) return null;
    final meta = user.userMetadata?['full_name'];
    if (meta is String && meta.trim().isNotEmpty) {
      return meta.trim().split(RegExp(r'\s+')).first;
    }
    final local = user.email?.split('@').first;
    if (local == null || local.isEmpty) return null;
    final cleaned = local.split(RegExp(r'[._-]')).first;
    if (cleaned.isEmpty) return null;
    return cleaned[0].toUpperCase() + cleaned.substring(1);
  }

  Stream<AuthState> get authStateChanges => supabase.auth.onAuthStateChange;
}

final authRepositoryProvider = Provider<AuthRepository>((ref) => AuthRepository());

final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges;
});
