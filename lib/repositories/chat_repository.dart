import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/chat_message.dart';

/// Kapselt den Firestore-Zugriff auf `groups/{groupId}/messages`. Firestore
/// Auto-ID pro Nachricht, chronologisch sortiert über den serverseitigen
/// `created_at`-Timestamp.
class ChatRepository {
  ChatRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _messages(String groupId) =>
      _firestore.collection('groups').doc(groupId).collection('messages');

  /// Live-Fenster der [limit] neuesten Nachrichten, älteste zuerst (so wie
  /// ein Chat gelesen wird). Kein unbegrenztes Laden der gesamten Historie.
  Stream<List<ChatMessage>> watchLatestMessages(String groupId, {int limit = 30}) {
    return _messages(groupId)
        .orderBy('created_at')
        .limitToLast(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(ChatMessage.fromFirestore).toList());
  }

  /// Eine Seite älterer Nachrichten vor [before], älteste zuerst - für
  /// manuelles Nachladen beim Hochscrollen.
  Future<List<ChatMessage>> loadOlderMessages(
    String groupId, {
    required DateTime before,
    int limit = 30,
  }) async {
    final snapshot = await _messages(groupId)
        .orderBy('created_at', descending: true)
        .where('created_at', isLessThan: Timestamp.fromDate(before))
        .limit(limit)
        .get();
    return snapshot.docs.reversed.map(ChatMessage.fromFirestore).toList();
  }

  /// Legt eine neue Nachricht an. `created_at` wird ausschließlich
  /// serverseitig gesetzt (`FieldValue.serverTimestamp()`) - die lokale
  /// Gerätezeit ist keine vertrauenswürdige Quelle.
  Future<void> sendMessage({
    required String groupId,
    required String senderUid,
    required String text,
  }) {
    return _messages(groupId).add({
      'sender_uid': senderUid,
      'text': text,
      'created_at': FieldValue.serverTimestamp(),
    });
  }
}
