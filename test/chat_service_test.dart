import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:film2watch/repositories/chat_repository.dart';
import 'package:film2watch/repositories/group_repository.dart';
import 'package:film2watch/services/chat_service.dart';
import 'package:film2watch/utils/chat_exceptions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatService', () {
    late FakeFirebaseFirestore firestore;
    late GroupRepository groupRepository;
    late ChatRepository chatRepository;
    late ChatService chatService;
    late String groupId;

    setUp(() async {
      firestore = FakeFirebaseFirestore();
      groupRepository = GroupRepository(firestore);
      chatRepository = ChatRepository(firestore);
      chatService = ChatService(chatRepository, groupRepository);

      final group = await groupRepository.createGroup(name: 'Filmabend', creatorUid: 'alice');
      groupId = group.id;
      await groupRepository.acceptInvitation(groupId: groupId, inviteeUid: 'bob');
    });

    test('Nachricht senden', () async {
      await chatService.sendMessage(groupId: groupId, senderUid: 'alice', text: 'Hallo!');

      final messages = await chatRepository.watchLatestMessages(groupId).first;
      expect(messages, hasLength(1));
      expect(messages.first.text, 'Hallo!');
    });

    test('leere Nachricht wird abgelehnt', () async {
      expect(
        () => chatService.sendMessage(groupId: groupId, senderUid: 'alice', text: ''),
        throwsA(isA<ChatActionException>()),
      );
    });

    test('Whitespace-only Nachricht wird abgelehnt', () async {
      expect(
        () => chatService.sendMessage(groupId: groupId, senderUid: 'alice', text: '   \n  '),
        throwsA(isA<ChatActionException>()),
      );
    });

    test('Nachricht mit exakt der maximalen Länge wird akzeptiert', () async {
      final text = 'x' * chatMaxMessageLength;
      await chatService.sendMessage(groupId: groupId, senderUid: 'alice', text: text);

      final messages = await chatRepository.watchLatestMessages(groupId).first;
      expect(messages.single.text!.length, chatMaxMessageLength);
    });

    test('zu lange Nachricht wird abgelehnt', () async {
      final text = 'x' * (chatMaxMessageLength + 1);
      expect(
        () => chatService.sendMessage(groupId: groupId, senderUid: 'alice', text: text),
        throwsA(isA<ChatActionException>()),
      );
    });

    test('sender_uid wird korrekt gespeichert', () async {
      await chatService.sendMessage(groupId: groupId, senderUid: 'bob', text: 'Von bob');

      final messages = await chatRepository.watchLatestMessages(groupId).first;
      expect(messages.single.senderUid, 'bob');
    });

    test('Stream liefert gesendete Nachrichten', () async {
      final emissions = <int>[];
      final subscription =
          chatRepository.watchLatestMessages(groupId).listen((msgs) => emissions.add(msgs.length));
      addTearDown(subscription.cancel);
      await Future.delayed(Duration.zero);

      await chatService.sendMessage(groupId: groupId, senderUid: 'alice', text: 'Erste Nachricht');
      await Future.delayed(Duration.zero);

      expect(emissions.last, 1);
    });

    test('Nachrichten werden chronologisch (älteste zuerst) sortiert', () async {
      await chatService.sendMessage(groupId: groupId, senderUid: 'alice', text: 'Eins');
      await Future.delayed(const Duration(milliseconds: 5));
      await chatService.sendMessage(groupId: groupId, senderUid: 'bob', text: 'Zwei');
      await Future.delayed(const Duration(milliseconds: 5));
      await chatService.sendMessage(groupId: groupId, senderUid: 'alice', text: 'Drei');

      final messages = await chatRepository.watchLatestMessages(groupId).first;
      expect(messages.map((m) => m.text).toList(), ['Eins', 'Zwei', 'Drei']);
    });

    test('Senden durch ein Nicht-Mitglied schlägt fehl', () async {
      expect(
        () => chatService.sendMessage(groupId: groupId, senderUid: 'carol', text: 'Ich bin fremd'),
        throwsA(isA<ChatActionException>()),
      );
    });
  });
}
