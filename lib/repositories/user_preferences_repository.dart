import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/user_genre_preferences.dart';

/// Kapselt den (rein lesenden) Firestore-Zugriff auf `user_preferences/{uid}`
/// - geschrieben wird dieses Dokument ausschließlich serverseitig von der
/// Cloud Function `functions/userPreferences.js` (Admin-SDK, umgeht Rules);
/// die Firestore Rules verbieten jeden clientseitigen Schreibzugriff
/// (`allow write: if false`).
class UserPreferencesRepository {
  UserPreferencesRepository(this._firestore);

  final FirebaseFirestore _firestore;

  /// Liefert die aktuellen Genre-Präferenzen von [uid]. Existiert noch kein
  /// Dokument (z. B. ein neuer User ohne ausgewertete Swipe-Historie), wird
  /// [UserGenrePreferences.empty] zurückgegeben - kein Fehler, kein
  /// künstlicher Platzhalterwert.
  Future<UserGenrePreferences> getPreferences(String uid) async {
    final snapshot = await _firestore.collection('user_preferences').doc(uid).get();
    if (!snapshot.exists) return UserGenrePreferences.empty;
    return UserGenrePreferences.fromFirestore(snapshot);
  }
}
