import 'package:cloud_firestore/cloud_firestore.dart';

/// Kapselt den (rein lesenden) Firestore-Zugriff auf `premium_status/{uid}`
/// (§15 der Master-Spezifikation: Premium Abo). Dieses Dokument wird
/// ausschließlich serverseitig geschrieben - die Firestore Rules verbieten
/// jeden clientseitigen Schreibzugriff (`allow write: if false`), damit kein
/// Nutzer sich selbst Premium-Rechte einräumen kann.
///
/// WICHTIG: Der tatsächliche Kaufweg (§18: RevenueCat, App-Store-/
/// Play-Store-Abo) ist nicht Teil dieses Schritts - es gibt in dieser
/// Umgebung keine Zahlungs-/Store-Zugangsdaten. Dieses Repository
/// implementiert ausschließlich die Lese-/Gating-Seite; wie
/// `premium_status/{uid}.is_premium` tatsächlich auf `true` gesetzt wird,
/// bleibt offene externe Konfiguration (analog zu Google/Apple Sign-In).
class PremiumRepository {
  PremiumRepository(this._firestore);

  final FirebaseFirestore _firestore;

  /// `false`, wenn kein Dokument existiert (Normalfall für einen Free-User) -
  /// kein Fehler, kein künstlicher Platzhalterwert.
  Future<bool> isPremium(String uid) async {
    final snapshot = await _firestore.collection('premium_status').doc(uid).get();
    if (!snapshot.exists) return false;
    return snapshot.data()?['is_premium'] == true;
  }

  /// Reaktive Variante von [isPremium] - für UI, die den Premium-Status live
  /// anzeigen soll (z. B. eine ehrliche Premium-Kennzeichnung am
  /// Super-Swipe-Button), analog zu `UserRepository.watchUser`. Die
  /// tatsächliche, sicherheitsrelevante Durchsetzung bleibt unabhängig davon
  /// immer serverseitig (Firestore Rules `isPremium()`) - dieser Stream dient
  /// ausschließlich der Darstellung, niemals als alleinige Zugriffskontrolle.
  Stream<bool> watchIsPremium(String uid) {
    return _firestore
        .collection('premium_status')
        .doc(uid)
        .snapshots()
        .map((snapshot) => snapshot.data()?['is_premium'] == true);
  }
}
