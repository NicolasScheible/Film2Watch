import 'package:firebase_auth/firebase_auth.dart';

import '../repositories/auth_repository.dart';
import '../repositories/user_repository.dart';

/// Orchestriert Authentifizierung (Firebase Auth) und das zugehörige
/// User-Dokument in Firestore. Die UI spricht ausschließlich mit diesem
/// Service, nie direkt mit Firebase Auth oder Firestore.
class AuthService {
  AuthService(this._authRepository, this._userRepository);

  final AuthRepository _authRepository;
  final UserRepository _userRepository;

  Stream<User?> authStateChanges() => _authRepository.authStateChanges();

  User? get currentUser => _authRepository.currentUser;

  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final credential = await _authRepository.signInWithEmail(
      email: email,
      password: password,
    );
    await _ensureUserDocument(credential.user!);
  }

  Future<void> registerWithEmail({
    required String name,
    required String email,
    required String password,
  }) async {
    final credential = await _authRepository.registerWithEmail(
      email: email,
      password: password,
    );
    final user = credential.user!;
    await user.updateDisplayName(name);
    await _userRepository.ensureUserDocument(
      uid: user.uid,
      email: user.email ?? email,
      name: name,
      profilePicture: user.photoURL,
    );
  }

  Future<void> sendPasswordResetEmail(String email) {
    return _authRepository.sendPasswordResetEmail(email);
  }

  Future<void> signInWithGoogle() async {
    final credential = await _authRepository.signInWithGoogle();
    await _ensureUserDocument(credential.user!);
  }

  Future<void> signInWithApple() async {
    final credential = await _authRepository.signInWithApple();
    await _ensureUserDocument(credential.user!);
  }

  Future<void> signOut() => _authRepository.signOut();

  Future<void> _ensureUserDocument(User user) {
    return _userRepository.ensureUserDocument(
      uid: user.uid,
      email: user.email ?? '',
      name: user.displayName ?? '',
      profilePicture: user.photoURL,
    );
  }
}
