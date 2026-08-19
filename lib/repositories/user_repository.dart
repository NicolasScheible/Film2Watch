import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/public_profile.dart';
import '../models/user_model.dart';

/// Wird intern geworfen, wenn ein generierter Freundescode während der
/// Transaktion bereits vergeben ist, damit [UserRepository] einen neuen
/// Kandidaten versuchen kann.
class _FriendCodeCollisionException implements Exception {}

/// Kapselt den Firestore-Zugriff auf die `users`-Collection (privates
/// Profil), die `public_profiles`-Collection (für andere User sichtbare
/// Teilmenge) sowie die `friend_codes`-Lookup-Collection, mit der die
/// Eindeutigkeit von Freundescodes geprüft wird (siehe firestore.rules).
class UserRepository {
  UserRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  CollectionReference<Map<String, dynamic>> get _publicProfiles =>
      _firestore.collection('public_profiles');

  CollectionReference<Map<String, dynamic>> get _friendCodes =>
      _firestore.collection('friend_codes');

  Future<AppUser?> getUser(String uid) async {
    final snapshot = await _users.doc(uid).get();
    if (!snapshot.exists) return null;
    return AppUser.fromFirestore(snapshot);
  }

  /// Reagiert live auf Änderungen am User-Dokument (z. B. nach dem
  /// Ergänzen des Namens).
  Stream<AppUser?> watchUser(String uid) {
    return _users
        .doc(uid)
        .snapshots()
        .map((snapshot) => snapshot.exists ? AppUser.fromFirestore(snapshot) : null);
  }

  /// Löst einen Freundescode (z. B. `FILM-4821`) zur zugehörigen uid auf,
  /// oder `null`, falls kein User diesen Code besitzt.
  Future<String?> resolveFriendCode(String code) async {
    final snapshot = await _friendCodes.doc(code).get();
    if (!snapshot.exists) return null;
    return snapshot.data()?['uid'] as String?;
  }

  Future<PublicProfile?> getPublicProfile(String uid) async {
    final snapshot = await _publicProfiles.doc(uid).get();
    if (!snapshot.exists) return null;
    return PublicProfile.fromFirestore(snapshot);
  }

  Stream<PublicProfile?> watchPublicProfile(String uid) {
    return _publicProfiles
        .doc(uid)
        .snapshots()
        .map((snapshot) => snapshot.exists ? PublicProfile.fromFirestore(snapshot) : null);
  }

  /// Setzt den Namen des Users. `email`, `friend_code` und `created_at`
  /// bleiben unangetastet (`users/{uid}` und `public_profiles/{uid}` werden
  /// gemeinsam in einem Batch aktualisiert, damit beide nie auseinanderlaufen).
  Future<void> updateName(String uid, String name) {
    final batch = _firestore.batch();
    batch.update(_users.doc(uid), {'name': name});
    batch.update(_publicProfiles.doc(uid), {'name': name});
    return batch.commit();
  }

  /// Erstellt das User-Dokument samt öffentlichem Profil und eindeutigem
  /// Freundescode nur, wenn es noch nicht existiert. Ein bestehendes Profil
  /// wird dabei niemals überschrieben. Die Eindeutigkeitsprüfung des
  /// Freundescodes und das Anlegen von `users/{uid}` + `public_profiles/{uid}`
  /// + `friend_codes/{code}` laufen atomar in einer Transaktion.
  Future<AppUser> ensureUserDocument({
    required String uid,
    required String email,
    String name = '',
    String? profilePicture,
  }) async {
    final userDocRef = _users.doc(uid);

    final existing = await userDocRef.get();
    if (existing.exists) return AppUser.fromFirestore(existing);

    const maxAttempts = 10;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final candidateCode = _randomFriendCode();
      final friendCodeRef = _friendCodes.doc(candidateCode);
      final publicProfileRef = _publicProfiles.doc(uid);
      final newUser = AppUser(
        uid: uid,
        name: name,
        email: email,
        profilePicture: profilePicture,
        friendCode: candidateCode,
        createdAt: DateTime.now(),
      );
      final publicProfile = PublicProfile(
        uid: uid,
        name: name,
        profilePicture: profilePicture,
        friendCode: candidateCode,
      );

      try {
        await _firestore.runTransaction((transaction) async {
          final userSnapshot = await transaction.get(userDocRef);
          if (userSnapshot.exists) return;

          final codeSnapshot = await transaction.get(friendCodeRef);
          if (codeSnapshot.exists) throw _FriendCodeCollisionException();

          transaction.set(userDocRef, newUser.toFirestore());
          transaction.set(publicProfileRef, publicProfile.toFirestore());
          transaction.set(friendCodeRef, {'uid': uid});
        });
      } on _FriendCodeCollisionException {
        continue;
      }

      final finalSnapshot = await userDocRef.get();
      return finalSnapshot.exists ? AppUser.fromFirestore(finalSnapshot) : newUser;
    }

    throw StateError(
      'Konnte nach $maxAttempts Versuchen keinen eindeutigen Freundescode generieren.',
    );
  }

  String _randomFriendCode() {
    final random = Random.secure();
    final digits = List.generate(4, (_) => random.nextInt(10)).join();
    return 'FILM-$digits';
  }
}
