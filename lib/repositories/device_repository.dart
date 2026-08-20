import 'package:cloud_firestore/cloud_firestore.dart';

/// Kapselt den Firestore-Zugriff auf `users/{uid}/devices`. Dokument-ID ist
/// deterministisch der FCM-Token - ein erneutes Registrieren desselben
/// Tokens (z. B. bei jedem App-Start) erzeugt kein Duplikat, sondern
/// aktualisiert nur `updated_at`; `created_at` bleibt dabei unangetastet.
class DeviceRepository {
  DeviceRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _devices(String uid) =>
      _firestore.collection('users').doc(uid).collection('devices');

  /// Registriert das aktuelle Gerät oder aktualisiert `updated_at`, falls der
  /// Token bereits bekannt ist (z. B. erneuter App-Start mit unverändertem
  /// Token).
  Future<void> registerDevice({
    required String uid,
    required String token,
    required String platform,
  }) async {
    final ref = _devices(uid).doc(token);
    final existing = await ref.get();

    if (existing.exists) {
      await ref.update({
        'platform': platform,
        'updated_at': FieldValue.serverTimestamp(),
      });
      return;
    }

    await ref.set({
      'token': token,
      'platform': platform,
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  /// Entfernt ein einzelnes Gerät (Token-Refresh: alter Token wird ungültig;
  /// Logout: eigenes Gerät abmelden). Betrifft ausschließlich das eigene
  /// Gerät des aufrufenden Users - nie fremde Geräte.
  Future<void> removeDevice({required String uid, required String token}) {
    return _devices(uid).doc(token).delete();
  }
}
