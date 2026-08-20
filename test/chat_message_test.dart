import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:film2watch/models/chat_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatMessage.fromFirestore', () {
    late FakeFirebaseFirestore firestore;

    setUp(() {
      firestore = FakeFirebaseFirestore();
    });

    test('Dokumente ohne "type"-Feld werden als Text-Nachricht gelesen (Rückwärtskompatibilität)',
        () async {
      final ref = firestore.collection('groups/g1/messages').doc('msg1');
      await ref.set({
        'sender_uid': 'alice',
        'text': 'Hallo!',
        'created_at': Timestamp.now(),
      });

      final message = ChatMessage.fromFirestore(await ref.get());

      expect(message.type, ChatMessageType.text);
      expect(message.senderUid, 'alice');
      expect(message.text, 'Hallo!');
      expect(message.movieId, isNull);
    });

    test('type "text" wird als Text-Nachricht gelesen', () async {
      final ref = firestore.collection('groups/g1/messages').doc('msg2');
      await ref.set({
        'type': 'text',
        'sender_uid': 'alice',
        'text': 'Hallo!',
        'created_at': Timestamp.now(),
      });

      final message = ChatMessage.fromFirestore(await ref.get());

      expect(message.type, ChatMessageType.text);
      expect(message.senderUid, 'alice');
      expect(message.text, 'Hallo!');
    });

    test('type "match" wird als Match-Systemnachricht gelesen, ohne sender_uid/text', () async {
      final ref = firestore.collection('groups/g1/messages').doc('msg3');
      await ref.set({
        'type': 'match',
        'movie_id': 550,
        'created_at': Timestamp.now(),
      });

      final message = ChatMessage.fromFirestore(await ref.get());

      expect(message.type, ChatMessageType.match);
      expect(message.movieId, 550);
      expect(message.senderUid, isNull);
      expect(message.text, isNull);
    });

    test('unbekannter type-Wert fällt sicher auf Text zurück', () async {
      final ref = firestore.collection('groups/g1/messages').doc('msg4');
      await ref.set({
        'type': 'irgendwas_neues',
        'sender_uid': 'alice',
        'text': 'Hallo!',
        'created_at': Timestamp.now(),
      });

      final message = ChatMessage.fromFirestore(await ref.get());

      expect(message.type, ChatMessageType.text);
    });
  });
}
