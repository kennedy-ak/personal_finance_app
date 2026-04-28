import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_client.dart';

class AuthRepository {
  Future<AuthResponse> signIn({required String email, required String password}) {
    return supabase.auth.signInWithPassword(email: email, password: password);
  }

  Future<AuthResponse> signUp({required String email, required String password}) {
    return supabase.auth.signUp(email: email, password: password);
  }

  Future<void> signOut() => supabase.auth.signOut();

  User? get currentUser => supabase.auth.currentUser;

  Stream<AuthState> get authStateChanges => supabase.auth.onAuthStateChange;
}

final authRepositoryProvider = Provider<AuthRepository>((ref) => AuthRepository());

final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges;
});
