import 'package:cloud_firestore/cloud_firestore.dart';

/// Art einer Chat-Nachricht. `text` sind normale Nutzer-Nachrichten,
/// `match` sind serverseitig erzeugte System-Nachrichten (siehe
/// `functions/postMatchChatMessage.js`), die ein neues Match ankündigen.
enum ChatMessageType {
  text,
  match;

  static ChatMessageType fromString(String? value) {
    return ChatMessageType.values.firstWhere(
      (type) => type.name == value,
      orElse: () => ChatMessageType.text,
    );
  }
}

/// Eine Chat-Nachricht (`groups/{groupId}/messages/{messageId}`).
///
/// Enthält bewusst weder `sender_name` noch `sender_profile_picture`: beide
/// lassen sich zuverlässig über `public_profiles/{senderUid}` nachschlagen
/// (siehe `publicProfileProvider`) - eine Kopie hier wäre unnötige
/// Redundanz und könnte veralten, wenn sich Name/Bild später ändern.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.type,
    this.senderUid,
    this.text,
    this.movieId,
    required this.createdAt,
  });

  final String id;
  final ChatMessageType type;

  /// Nur bei [ChatMessageType.text] gesetzt.
  final String? senderUid;

  /// Nur bei [ChatMessageType.text] gesetzt.
  final String? text;

  /// Nur bei [ChatMessageType.match] gesetzt - der TMDB-Film, der zum Match
  /// geführt hat. Wird clientseitig über `movieDetailsProvider` aufgelöst
  /// (Cloud Functions haben bewusst keinen TMDB-Zugriff).
  final int? movieId;

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
    // Bestehende Dokumente haben kein `type`-Feld - fällt auf `text` zurück,
    // damit alte Nachrichten unverändert weiter angezeigt werden.
    final type = ChatMessageType.fromString(data['type'] as String?);
    return ChatMessage(
      id: doc.id,
      type: type,
      senderUid: type == ChatMessageType.text ? (data['sender_uid'] as String? ?? '') : null,
      text: type == ChatMessageType.text ? (data['text'] as String? ?? '') : null,
      movieId: type == ChatMessageType.match ? (data['movie_id'] as int?) : null,
      createdAt: createdAtValue is Timestamp ? createdAtValue.toDate() : DateTime.now(),
    );
  }
}
