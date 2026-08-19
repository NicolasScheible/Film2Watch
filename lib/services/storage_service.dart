import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';

/// Kapselt den Zugriff auf Firebase Storage für Profil- und Gruppenbilder.
/// Kennt keine Firestore-Details - das Aktualisieren von
/// `users/{uid}.profile_picture` bzw. `groups/{groupId}.photo_url` bleibt
/// Aufgabe der jeweiligen Repositories.
class StorageService {
  StorageService(this._storage);

  final FirebaseStorage _storage;

  /// Maximale Upload-Größe - muss mit der Prüfung in `storage.rules`
  /// übereinstimmen.
  static const int maxUploadBytes = 5 * 1024 * 1024;

  Reference _profileImageRef(String uid) =>
      _storage.ref('profile_images/$uid/profile.jpg');

  Reference _groupImageRef(String groupId) =>
      _storage.ref('group_images/$groupId/group.jpg');

  /// Lädt das Profilbild hoch (überschreibt ein eventuell vorhandenes altes
  /// Bild am selben, festen Pfad) und gibt die Download-URL zurück.
  Future<String> uploadProfileImage({required String uid, required File file}) async {
    final ref = _profileImageRef(uid);
    await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
    return ref.getDownloadURL();
  }

  /// Löscht das Profilbild. Kein Fehler, falls ohnehin keins vorhanden ist.
  Future<void> deleteProfileImage(String uid) async {
    await _deleteIfExists(_profileImageRef(uid));
  }

  /// Lädt das Gruppenbild hoch (überschreibt ein eventuell vorhandenes altes
  /// Bild am selben, festen Pfad) und gibt die Download-URL zurück.
  Future<String> uploadGroupImage({required String groupId, required File file}) async {
    final ref = _groupImageRef(groupId);
    await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
    return ref.getDownloadURL();
  }

  /// Löscht das Gruppenbild. Kein Fehler, falls ohnehin keins vorhanden ist.
  Future<void> deleteGroupImage(String groupId) async {
    await _deleteIfExists(_groupImageRef(groupId));
  }

  Future<void> _deleteIfExists(Reference ref) async {
    try {
      await ref.delete();
    } on FirebaseException catch (e) {
      if (e.code == 'object-not-found') return;
      rethrow;
    }
  }
}
