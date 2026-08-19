import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../utils/auth_exceptions.dart';

/// Kapselt den direkten Zugriff auf Firebase Authentication sowie die
/// Google- und Apple-Sign-In-SDKs. Enthält keine Firestore- oder UI-Logik.
class AuthRepository {
  AuthRepository(this._auth);

  final FirebaseAuth _auth;

  bool _googleSignInInitialized = false;

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  Future<UserCredential> signInWithEmail({
    required String email,
    required String password,
  }) {
    return _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<UserCredential> registerWithEmail({
    required String email,
    required String password,
  }) {
    return _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  Future<void> sendPasswordResetEmail(String email) {
    return _auth.sendPasswordResetEmail(email: email);
  }

  Future<void> signOut() async {
    await _auth.signOut();
    if (_googleSignInInitialized) {
      await GoogleSignIn.instance.signOut();
    }
  }

  /// Meldet den Nutzer über Google an.
  ///
  /// Benötigt einen für dieses Firebase-Projekt registrierten OAuth-Client.
  /// Ist keiner vorhanden, wirft der Aufruf eine [GoogleSignInException]
  /// mit Code `clientConfigurationError` (kein Fake-Login, echter Fehler).
  Future<UserCredential> signInWithGoogle() async {
    if (!_googleSignInInitialized) {
      await GoogleSignIn.instance.initialize();
      _googleSignInInitialized = true;
    }
    final account = await GoogleSignIn.instance.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw const AuthConfigurationException(
        'Google-Anmeldung hat kein ID-Token zurückgegeben.',
      );
    }
    final credential = GoogleAuthProvider.credential(idToken: idToken);
    return _auth.signInWithCredential(credential);
  }

  /// Meldet den Nutzer über Sign in with Apple an (nativer Flow).
  ///
  /// Benötigt die Sign-In-with-Apple-Capability im Apple Developer Account
  /// sowie den aktivierten Apple-Provider in der Firebase-Konsole.
  Future<UserCredential> signInWithApple() async {
    final rawNonce = _generateNonce();
    final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

    final appleCredential = await SignInWithApple.getAppleIDCredential(
      scopes: const [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: hashedNonce,
    );

    final oauthCredential = OAuthProvider('apple.com').credential(
      idToken: appleCredential.identityToken,
      rawNonce: rawNonce,
    );

    final userCredential = await _auth.signInWithCredential(oauthCredential);

    // Apple liefert Vor-/Nachname nur bei der allerersten Autorisierung.
    final fullName = [
      appleCredential.givenName,
      appleCredential.familyName,
    ].whereType<String>().where((part) => part.trim().isNotEmpty).join(' ');
    if (fullName.isNotEmpty && userCredential.user?.displayName == null) {
      await userCredential.user?.updateDisplayName(fullName);
    }

    return userCredential;
  }

  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => charset[random.nextInt(charset.length)],
    ).join();
  }
}
