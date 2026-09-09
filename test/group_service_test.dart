import 'dart:io';
import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:film2watch/models/group_member.dart';
import 'package:film2watch/repositories/friend_repository.dart';
import 'package:film2watch/repositories/group_repository.dart';
import 'package:film2watch/repositories/premium_repository.dart';
import 'package:film2watch/repositories/user_repository.dart';
import 'package:film2watch/services/group_service.dart';
import 'package:film2watch/services/storage_service.dart';
import 'package:film2watch/utils/group_exceptions.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late UserRepository userRepository;
  late FriendRepository friendRepository;
  late GroupRepository groupRepository;
  late PremiumRepository premiumRepository;
  late GroupService groupService;
  late File imageFile;

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    userRepository = UserRepository(firestore);
    friendRepository = FriendRepository(firestore);
    groupRepository = GroupRepository(firestore);
    premiumRepository = PremiumRepository(firestore);
    groupService = GroupService(
      groupRepository,
      friendRepository,
      StorageService(MockFirebaseStorage()),
      premiumRepository,
    );

    for (final uid in ['alice', 'bob', 'carol']) {
      await userRepository.ensureUserDocument(
        uid: uid,
        email: '$uid@film2watch.app',
        name: uid,
      );
    }
    // alice und bob sind Freunde, carol nicht.
    await friendRepository.sendFriendRequest(fromUid: 'alice', toUid: 'bob');
    await friendRepository.acceptRequest(fromUid: 'alice', toUid: 'bob');

    imageFile = File(
      '${Directory.systemTemp.path}/film2watch_group_test_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    await imageFile.writeAsBytes(Uint8List.fromList(List.filled(1024, 1)));
    addTearDown(() => imageFile.delete());
  });

  test('Benutzer kann Gruppe erstellen', () async {
    final group = await groupService.createGroup(name: 'Filmabend', creatorUid: 'alice');

    expect(group.name, 'Filmabend');
    expect(await groupRepository.getGroup(group.id), isNotNull);
  });

  test('Gruppe hat Ersteller als Admin', () async {
    final group = await groupService.createGroup(name: 'Filmabend', creatorUid: 'alice');

    final member = await groupRepository.getMember(group.id, 'alice');
    expect(member, isNotNull);
    expect(member!.role, GroupRole.admin);
  });

  test('Gruppenname wird validiert', () async {
    expect(
      () => groupService.createGroup(name: '   ', creatorUid: 'alice'),
      throwsA(isA<GroupActionException>()),
    );
    expect(
      () => groupService.createGroup(name: 'x', creatorUid: 'alice'),
      throwsA(isA<GroupActionException>()),
    );
  });

  test('Admin kann Freund einladen', () async {
    final group = await groupService.createGroup(name: 'Filmabend', creatorUid: 'alice');

    await groupService.inviteFriend(groupId: group.id, inviterUid: 'alice', inviteeUid: 'bob');

    expect(await groupRepository.invitationExists(group.id, 'bob'), isTrue);
  });

  test('Nicht-Freund kann nicht eingeladen werden', () async {
    final group = await groupService.createGroup(name: 'Filmabend', creatorUid: 'alice');

    expect(
      () => groupService.inviteFriend(groupId: group.id, inviterUid: 'alice', inviteeUid: 'carol'),
      throwsA(isA<GroupActionException>()),
    );
  });

  test('doppelte Einladung wird verhindert', () async {
    final group = await groupService.createGroup(name: 'Filmabend', creatorUid: 'alice');
    await groupService.inviteFriend(groupId: group.id, inviterUid: 'alice', inviteeUid: 'bob');

    expect(
      () => groupService.inviteFriend(groupId: group.id, inviterUid: 'alice', inviteeUid: 'bob'),
      throwsA(isA<GroupActionException>()),
    );
  });

  test('Einladung kann angenommen werden und Mitglied erscheint in Gruppe', () async {
    final group = await groupService.createGroup(name: 'Filmabend', creatorUid: 'alice');
    await groupService.inviteFriend(groupId: group.id, inviterUid: 'alice', inviteeUid: 'bob');

    await groupService.acceptInvitation(groupId: group.id, inviteeUid: 'bob');

    expect(await groupRepository.invitationExists(group.id, 'bob'), isFalse);
    final member = await groupRepository.getMember(group.id, 'bob');
    expect(member, isNotNull);
    expect(member!.role, GroupRole.member);
    expect(await groupRepository.memberCount(group.id), 2);
  });

  test('Einladung kann abgelehnt werden', () async {
    final group = await groupService.createGroup(name: 'Filmabend', creatorUid: 'alice');
    await groupService.inviteFriend(groupId: group.id, inviterUid: 'alice', inviteeUid: 'bob');

    await groupService.declineInvitation(groupId: group.id, inviteeUid: 'bob');

    expect(await groupRepository.invitationExists(group.id, 'bob'), isFalse);
    expect(await groupRepository.getMember(group.id, 'bob'), isNull);
  });

  test('Mitglied kann Gruppe verlassen', () async {
    final group = await groupService.createGroup(name: 'Filmabend', creatorUid: 'alice');
    await groupService.inviteFriend(groupId: group.id, inviterUid: 'alice', inviteeUid: 'bob');
    await groupService.acceptInvitation(groupId: group.id, inviteeUid: 'bob');

    await groupService.leaveGroup(groupId: group.id, uid: 'bob');

    expect(await groupRepository.getMember(group.id, 'bob'), isNull);
    expect(await groupRepository.getGroup(group.id), isNotNull);
  });

  test('Admin kann Mitglied entfernen', () async {
    final group = await groupService.createGroup(name: 'Filmabend', creatorUid: 'alice');
    await groupService.inviteFriend(groupId: group.id, inviterUid: 'alice', inviteeUid: 'bob');
    await groupService.acceptInvitation(groupId: group.id, inviteeUid: 'bob');

    await groupService.removeMember(groupId: group.id, callerUid: 'alice', targetUid: 'bob');

    expect(await groupRepository.getMember(group.id, 'bob'), isNull);
  });

  test('normales Mitglied kann kein Mitglied entfernen', () async {
    final group = await groupService.createGroup(name: 'Filmabend', creatorUid: 'alice');
    await groupService.inviteFriend(groupId: group.id, inviterUid: 'alice', inviteeUid: 'bob');
    await groupService.acceptInvitation(groupId: group.id, inviteeUid: 'bob');

    expect(
      () => groupService.removeMember(groupId: group.id, callerUid: 'bob', targetUid: 'alice'),
      throwsA(isA<GroupActionException>()),
    );
  });

  test('normales Mitglied kann Gruppe nicht löschen', () async {
    final group = await groupService.createGroup(name: 'Filmabend', creatorUid: 'alice');
    await groupService.inviteFriend(groupId: group.id, inviterUid: 'alice', inviteeUid: 'bob');
    await groupService.acceptInvitation(groupId: group.id, inviteeUid: 'bob');

    expect(
      () => groupService.deleteGroup(groupId: group.id, callerUid: 'bob'),
      throwsA(isA<GroupActionException>()),
    );
  });

  test('Admin kann Gruppe löschen', () async {
    final group = await groupService.createGroup(name: 'Filmabend', creatorUid: 'alice');
    await groupService.inviteFriend(groupId: group.id, inviterUid: 'alice', inviteeUid: 'bob');
    await groupService.acceptInvitation(groupId: group.id, inviteeUid: 'bob');

    await groupService.deleteGroup(groupId: group.id, callerUid: 'alice');

    expect(await groupRepository.getGroup(group.id), isNull);
    expect(await groupRepository.getMember(group.id, 'alice'), isNull);
    expect(await groupRepository.getMember(group.id, 'bob'), isNull);
  });

  test('Admin kann nicht einfach die Gruppe verlassen, solange weitere Mitglieder da sind', () async {
    final group = await groupService.createGroup(name: 'Filmabend', creatorUid: 'alice');
    await groupService.inviteFriend(groupId: group.id, inviterUid: 'alice', inviteeUid: 'bob');
    await groupService.acceptInvitation(groupId: group.id, inviteeUid: 'bob');

    expect(
      () => groupService.leaveGroup(groupId: group.id, uid: 'alice'),
      throwsA(isA<GroupActionException>()),
    );

    // Nach Admin-Übertragung darf der ehemalige Admin ganz normal verlassen.
    await groupRepository.transferAdmin(
      groupId: group.id,
      currentAdminUid: 'alice',
      newAdminUid: 'bob',
    );
    await groupService.leaveGroup(groupId: group.id, uid: 'alice');
    expect(await groupRepository.getMember(group.id, 'alice'), isNull);
  });

  test('Admin als letztes Mitglied kann die Gruppe verlassen (Gruppe wird gelöscht)', () async {
    final group = await groupService.createGroup(name: 'Filmabend', creatorUid: 'alice');

    await groupService.leaveGroup(groupId: group.id, uid: 'alice');

    expect(await groupRepository.getGroup(group.id), isNull);
  });

  test('Gruppenbild-Upload funktioniert', () async {
    final group = await groupService.createGroup(name: 'Filmabend', creatorUid: 'alice');

    await groupService.uploadGroupImage(groupId: group.id, callerUid: 'alice', file: imageFile);

    final updated = await groupRepository.getGroup(group.id);
    expect(updated!.photoUrl, isNotNull);
    expect(updated.photoUrl, isNotEmpty);
  });

  test('fremder Benutzer darf Gruppenbild nicht verändern', () async {
    final group = await groupService.createGroup(name: 'Filmabend', creatorUid: 'alice');
    await groupService.inviteFriend(groupId: group.id, inviterUid: 'alice', inviteeUid: 'bob');
    await groupService.acceptInvitation(groupId: group.id, inviteeUid: 'bob');

    expect(
      () => groupService.uploadGroupImage(groupId: group.id, callerUid: 'bob', file: imageFile),
      throwsA(isA<GroupActionException>()),
    );
  });

  group('Free-Gruppen-Limit (§15)', () {
    test('ein Free-User kann genau 3 Gruppen anlegen, die 4. wird abgelehnt', () async {
      await groupService.createGroup(name: 'Gruppe 1', creatorUid: 'alice');
      await groupService.createGroup(name: 'Gruppe 2', creatorUid: 'alice');
      await groupService.createGroup(name: 'Gruppe 3', creatorUid: 'alice');
      expect(await groupRepository.myGroupCount('alice'), 3);

      expect(
        () => groupService.createGroup(name: 'Gruppe 4', creatorUid: 'alice'),
        throwsA(isA<GroupActionException>()),
      );
      // Die abgelehnte 4. Gruppe darf nicht als verwaiste Gruppe ohne
      // erfolgreiche Mitgliedschaft zurückbleiben - der Limit-Check greift
      // schon vor dem eigentlichen Anlegen, es entsteht also gar kein
      // Gruppendokument.
      expect(await groupRepository.myGroupCount('alice'), 3);
    });

    test('ein Free-User kann das Limit nicht durch Annehmen einer Einladung umgehen', () async {
      // alice ist hier bewusst Premium: sie soll selbst 4 Gruppen anlegen
      // können, um bob (den eigentlichen Free-User unter Test) in alle 4
      // einladen zu können - ihr eigener Premium-Status ist für diesen Test
      // irrelevant, nur bobs Free-Limit wird geprüft.
      await firestore.collection('premium_status').doc('alice').set({'is_premium': true});
      final group1 = await groupService.createGroup(name: 'Gruppe 1', creatorUid: 'alice');
      final group2 = await groupService.createGroup(name: 'Gruppe 2', creatorUid: 'alice');
      final group3 = await groupService.createGroup(name: 'Gruppe 3', creatorUid: 'alice');
      final group4 = await groupService.createGroup(name: 'Gruppe 4', creatorUid: 'alice');

      for (final group in [group1, group2, group3]) {
        await groupService.inviteFriend(groupId: group.id, inviterUid: 'alice', inviteeUid: 'bob');
        await groupService.acceptInvitation(groupId: group.id, inviteeUid: 'bob');
      }
      expect(await groupRepository.myGroupCount('bob'), 3);

      await groupService.inviteFriend(groupId: group4.id, inviterUid: 'alice', inviteeUid: 'bob');
      expect(
        () => groupService.acceptInvitation(groupId: group4.id, inviteeUid: 'bob'),
        throwsA(isA<GroupActionException>()),
      );
      // Die Einladung bleibt bestehen (Ablehnung passiert vor dem
      // eigentlichen Annehmen) - bob könnte sie annehmen, sobald er Platz
      // hat (z. B. nach Verlassen einer anderen Gruppe) oder Premium wird.
      expect(await groupRepository.invitationExists(group4.id, 'bob'), isTrue);
      expect(await groupRepository.getMember(group4.id, 'bob'), isNull);
    });

    test('ein Premium-User kann mehr als 3 Gruppen anlegen', () async {
      await firestore.collection('premium_status').doc('alice').set({'is_premium': true});

      await groupService.createGroup(name: 'Gruppe 1', creatorUid: 'alice');
      await groupService.createGroup(name: 'Gruppe 2', creatorUid: 'alice');
      await groupService.createGroup(name: 'Gruppe 3', creatorUid: 'alice');
      await groupService.createGroup(name: 'Gruppe 4', creatorUid: 'alice');

      expect(await groupRepository.myGroupCount('alice'), 4);
    });

    test('ein Premium-User kann trotz bereits 3 Gruppen einer weiteren Einladung folgen', () async {
      // alice ist hier ebenfalls Premium, aus demselben Grund wie im
      // vorherigen Test - unter Test steht ausschließlich bobs
      // Premium-Bypass.
      await firestore.collection('premium_status').doc('alice').set({'is_premium': true});
      final group1 = await groupService.createGroup(name: 'Gruppe 1', creatorUid: 'alice');
      final group2 = await groupService.createGroup(name: 'Gruppe 2', creatorUid: 'alice');
      final group3 = await groupService.createGroup(name: 'Gruppe 3', creatorUid: 'alice');
      final group4 = await groupService.createGroup(name: 'Gruppe 4', creatorUid: 'alice');
      await firestore.collection('premium_status').doc('bob').set({'is_premium': true});

      for (final group in [group1, group2, group3, group4]) {
        await groupService.inviteFriend(groupId: group.id, inviterUid: 'alice', inviteeUid: 'bob');
        await groupService.acceptInvitation(groupId: group.id, inviteeUid: 'bob');
      }

      expect(await groupRepository.myGroupCount('bob'), 4);
    });

    test('nach Verlassen einer Gruppe kann ein Free-User wieder eine neue anlegen', () async {
      final group1 = await groupService.createGroup(name: 'Gruppe 1', creatorUid: 'alice');
      await groupService.createGroup(name: 'Gruppe 2', creatorUid: 'alice');
      await groupService.createGroup(name: 'Gruppe 3', creatorUid: 'alice');

      await groupService.leaveGroup(groupId: group1.id, uid: 'alice');
      expect(await groupRepository.myGroupCount('alice'), 2);

      final group4 = await groupService.createGroup(name: 'Gruppe 4', creatorUid: 'alice');
      expect(await groupRepository.getGroup(group4.id), isNotNull);
    });
  });
}
