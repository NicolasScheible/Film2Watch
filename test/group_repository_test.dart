import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:film2watch/repositories/group_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// Testet `GroupRepository.watchCommonGroups` (§4: "gemeinsame Gruppen" im
/// Freundes-Profil) - liest ausschließlich den eigenen User-Group-Index
/// (`users/{currentUid}/groups/{groupId}`, siehe README
/// "Architekturentscheidung") und prüft pro eigener Gruppe direkt, ob der
/// Freund dort ebenfalls Mitglied ist. `fake_cloud_firestore` führt den
/// dafür zuständigen Cloud-Function-Trigger nicht aus, daher wird der Index
/// hier - wie überall sonst in den Tests dieser Codebase - direkt
/// nachgebildet.
Future<void> _seedGroup(
  FakeFirebaseFirestore firestore,
  String groupId, {
  required List<String> memberUids,
}) async {
  final now = DateTime.now();
  await firestore.collection('groups').doc(groupId).set({
    'id': groupId,
    'name': 'Gruppe $groupId',
    'photo_url': null,
    'created_by': memberUids.first,
    'created_at': now,
    'updated_at': now,
  });
  for (final uid in memberUids) {
    await firestore.collection('groups').doc(groupId).collection('members').doc(uid).set({
      'uid': uid,
      'role': uid == memberUids.first ? 'admin' : 'member',
      'joined_at': now,
    });
  }
}

Future<void> _seedUserGroupIndex(FakeFirebaseFirestore firestore, String uid, String groupId) {
  return firestore.collection('users').doc(uid).collection('groups').doc(groupId).set({
    'groupId': groupId,
  });
}

void main() {
  group('GroupRepository.watchCommonGroups', () {
    late FakeFirebaseFirestore firestore;
    late GroupRepository groupRepository;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      groupRepository = GroupRepository(firestore);
    });

    test('findet eine tatsächlich gemeinsame Gruppe', () async {
      await _seedGroup(firestore, 'g1', memberUids: ['alice', 'bob']);
      await _seedUserGroupIndex(firestore, 'alice', 'g1');

      final result =
          await groupRepository.watchCommonGroups(currentUid: 'alice', friendUid: 'bob').first;

      expect(result.map((g) => g.id), ['g1']);
    });

    test('schließt eine Gruppe aus, in der nur der Freund Mitglied ist (currentUid nicht Mitglied)', () async {
      // g2: bob und carol, alice ist NICHT Mitglied - darf für alice nicht
      // auftauchen, selbst wenn bob (der "Freund" aus alices Sicht) dort ist.
      await _seedGroup(firestore, 'g2', memberUids: ['bob', 'carol']);
      // alices eigener Index ist leer - sie ist in gar keiner Gruppe.

      final result =
          await groupRepository.watchCommonGroups(currentUid: 'alice', friendUid: 'bob').first;

      expect(result, isEmpty);
    });

    test('schließt eine eigene Gruppe aus, in der der Freund nicht Mitglied ist', () async {
      // g3: nur alice - eine eigene Gruppe von alice, in der bob nicht
      // Mitglied ist, darf nicht als "gemeinsam" erscheinen.
      await _seedGroup(firestore, 'g3', memberUids: ['alice']);
      await _seedUserGroupIndex(firestore, 'alice', 'g3');

      final result =
          await groupRepository.watchCommonGroups(currentUid: 'alice', friendUid: 'bob').first;

      expect(result, isEmpty);
    });

    test('findet mehrere gemeinsame Gruppen gleichzeitig', () async {
      await _seedGroup(firestore, 'g1', memberUids: ['alice', 'bob']);
      await _seedGroup(firestore, 'g4', memberUids: ['alice', 'bob', 'carol']);
      // g5 ist nur alices eigene Gruppe, bob ist dort nicht Mitglied.
      await _seedGroup(firestore, 'g5', memberUids: ['alice']);
      await _seedUserGroupIndex(firestore, 'alice', 'g1');
      await _seedUserGroupIndex(firestore, 'alice', 'g4');
      await _seedUserGroupIndex(firestore, 'alice', 'g5');

      final result =
          await groupRepository.watchCommonGroups(currentUid: 'alice', friendUid: 'bob').first;

      expect(result.map((g) => g.id).toSet(), {'g1', 'g4'});
    });

    test('liest niemals den User-Group-Index des Freundes, nur den eigenen', () async {
      // g6: bob und carol gemeinsam - taucht in bobs eigenem Index auf, aber
      // NICHT in alices. Das Ergebnis darf g6 unter keinen Umständen
      // enthalten, obwohl bob (der "Freund") dort Mitglied ist - alice ist
      // es nicht.
      await _seedGroup(firestore, 'g6', memberUids: ['bob', 'carol']);
      await _seedUserGroupIndex(firestore, 'bob', 'g6');
      // alice hat gar keinen eigenen Index-Eintrag.

      final result =
          await groupRepository.watchCommonGroups(currentUid: 'alice', friendUid: 'bob').first;

      expect(result, isEmpty);
    });
  });
}
