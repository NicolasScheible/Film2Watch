import 'package:cloud_firestore/cloud_firestore.dart';

/// Eine Chat-Nachricht (`groups/{groupId}/messages/{messageId}`).
///
/// Enthält bewusst weder `sender_name` noch `sender_profile_picture`: beide
/// lassen sich zuverlässig über `public_profiles/{senderUid}` nachschlagen
/// (siehe `publicProfileProvider`) - eine Kopie hier wäre unnötige
/// Redundanz und könnte veralten, wenn sich Name/Bild später ändern.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.senderUid,
    required this.text,
    required this.createdAt,
  });

  final String id;
  final String senderUid;
  final String text;

  /// Serverseitiger Timestamp (`FieldValue.serverTimestamp()`) - niemals die
  /// lokale Gerätezeit. Kann unmittelbar nach dem Senden kurzzeitig `null`
  /// sein (Firestore hat den Server-Timestamp einer gerade erst lokal
  /// sichtbaren, noch nicht bestätigten Schreibung noch nicht aufgelöst);
  /// in diesem seltenen Fall wird die aktuelle Zeit als Platzhalter für die
  /// Sortierung/Anzeige verwendet, bis der echte Wert eintrifft.
  final DateTime createdAt;

  factory ChatMessage.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    final createdAtValue = data['created_at'];
    return ChatMessage(
      id: doc.id,
      senderUid: data['sender_uid'] as String? ?? '',
      text: data['text'] as String? ?? '',
      createdAt: createdAtValue is Timestamp ? createdAtValue.toDate() : DateTime.now(),
    );
  }
}
