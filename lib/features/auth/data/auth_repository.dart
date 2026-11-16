import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_client.dart';

/// What a sign-in/sign-up attempt produced. With the FastAPI backend there is
/// no email-confirmation limbo: an account that exists is signed in.
class AuthResult {
  final AppUser user;
  const AuthResult(this.user);

  bool get signedIn => true;
}

class AuthRepository {
  Future<AuthResult> signIn({required String email, required String password}) async {
    final user = await api.signIn(email: email, password: password);
    return AuthResult(user);
  }

  /// [name] is stored as `full_name` on the user. The dashboard greets with
  /// it, which is why sign-up asks for it at all.
  Future<AuthResult> signUp({
    required String email,
    required String password,
    String? name,
  }) async {
    final trimmed = name?.trim();
    final user = await api.signUp(
      email: email,
      password: password,
      fullName: trimmed == null || trimmed.isEmpty ? null : trimmed,
    );
    return AuthResult(user);
  }

  /// The backend sends no email, so this cannot work — say so instead of
  /// pretending. (POST /auth/password-reset answers 501 with the same text.)
  Future<void> sendPasswordReset(String email) async {
    throw ApiException(
      501,
      'Password reset by email is not available. Change your password from '
      'Settings while signed in.',
    );
  }

  Future<void> signOut() => api.signOut();

  AppUser? get currentUser => api.currentUser;

  /// The name to greet with: what they typed at sign-up, else the local part
  /// of their email, else nothing.
  String? get displayName {
    final user = currentUser;
    if (user == null) return null;
    final meta = user.fullName;
    if (meta != null && meta.trim().isNotEmpty) {
      return meta.trim().split(RegExp(r'\s+')).first;
    }
    final local = user.email.split('@').first;
    if (local.isEmpty) return null;
    final cleaned = local.split(RegExp(r'[._-]')).first;
    if (cleaned.isEmpty) return null;
    return cleaned[0].toUpperCase() + cleaned.substring(1);
  }

  Stream<AppUser?> get authStateChanges => api.authStateChanges;
}

final authRepositoryProvider = Provider<AuthRepository>((ref) => AuthRepository());

final authStateProvider = StreamProvider<AppUser?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges;
});
