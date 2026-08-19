import 'dart:io';
import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:film2watch/models/group_member.dart';
import 'package:film2watch/repositories/friend_repository.dart';
import 'package:film2watch/repositories/group_repository.dart';
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
  late GroupService groupService;
  late File imageFile;

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    userRepository = UserRepository(firestore);
    friendRepository = FriendRepository(firestore);
    groupRepository = GroupRepository(firestore);
    groupService = GroupService(
      groupRepository,
      friendRepository,
      StorageService(MockFirebaseStorage()),
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
}
