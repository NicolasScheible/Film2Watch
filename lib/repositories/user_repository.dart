import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/user_model.dart';

/// Wird intern geworfen, wenn ein generierter Freundescode während der
/// Transaktion bereits vergeben ist, damit [UserRepository] einen neuen
/// Kandidaten versuchen kann.
class _FriendCodeCollisionException implements Exception {}

/// Kapselt den Firestore-Zugriff auf die `users`-Collection sowie die
/// `friend_codes`-Lookup-Collection, mit der die Eindeutigkeit von
/// Freundescodes geprüft wird, ohne dass Nutzer fremde User-Dokumente
/// lesen können müssen (siehe firestore.rules).
class UserRepository {
  UserRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

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

  Future<void> updateName(String uid, String name) {
    return _users.doc(uid).update({'name': name});
  }

  /// Erstellt das User-Dokument samt eindeutigem Freundescode nur, wenn es
  /// noch nicht existiert. Ein bestehendes Profil wird dabei niemals
  /// überschrieben. Die Eindeutigkeitsprüfung des Freundescodes und das
  /// Anlegen von `users/{uid}` + `friend_codes/{code}` laufen atomar in
  /// einer Transaktion.
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
      final newUser = AppUser(
        uid: uid,
        name: name,
        email: email,
        profilePicture: profilePicture,
        friendCode: candidateCode,
        createdAt: DateTime.now(),
      );

      try {
        await _firestore.runTransaction((transaction) async {
          final userSnapshot = await transaction.get(userDocRef);
          if (userSnapshot.exists) return;

          final codeSnapshot = await transaction.get(friendCodeRef);
          if (codeSnapshot.exists) throw _FriendCodeCollisionException();

          transaction.set(userDocRef, newUser.toFirestore());
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
