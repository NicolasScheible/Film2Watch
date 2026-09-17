import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:film2watch/providers/auth_provider.dart';
import 'package:film2watch/providers/group_provider.dart';
import 'package:film2watch/providers/match_provider.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Testet `pastMatchesWithFriendProvider` (§4: "vergangene Matches" im
/// Freundes-Profil) - kombiniert `commonGroupsWithFriendProvider` (liest den
/// User-Group-Index, siehe README "Architekturentscheidung") mit dem
/// bereits bestehenden, unveränderten `groupMatchesProvider` und filtert
/// nach `member_uids`. Testmuster analog zu
/// `all_my_matches_provider_test.dart`.
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

Future<void> _seedMatch(
  FakeFirebaseFirestore firestore,
  String groupId,
  int movieId,
  DateTime matchedAt, {
  required List<String> memberUids,
}) {
  return firestore.collection('groups').doc(groupId).collection('matches').doc('$movieId').set({
    'movie_id': movieId,
    'member_uids': memberUids,
    'matched_at': Timestamp.fromDate(matchedAt),
  });
}

void main() {
  group('pastMatchesWithFriendProvider', () {
    late FakeFirebaseFirestore firestore;
    late ProviderContainer container;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'alice', email: 'alice@film2watch.app'),
        signedIn: true,
      );
      container = ProviderContainer(
        overrides: [
          firebaseAuthProvider.overrideWithValue(auth),
          firestoreProvider.overrideWithValue(firestore),
        ],
      );
      addTearDown(container.dispose);
      container.listen(authStateChangesProvider, (previous, next) {});
    });

    /// Wartet, bis `commonGroupsWithFriendProvider` und alle
    /// `groupMatchesProvider`-Streams für [groupIds] ihr erstes
    /// Firestore-Snapshot geliefert haben - analog zu `settleMatches` in
    /// `statistics_provider_test.dart`, da `pastMatchesWithFriendProvider`
    /// diese nur per `.value` liest, ohne selbst darauf zu warten.
    Future<void> settle(String friendUid, List<String> groupIds) async {
      await container.read(authStateChangesProvider.future);
      container.listen(commonGroupsWithFriendProvider(friendUid), (previous, next) {});
      await container.read(commonGroupsWithFriendProvider(friendUid).future);
      for (final groupId in groupIds) {
        container.listen(groupMatchesProvider(groupId), (previous, next) {});
        await container.read(groupMatchesProvider(groupId).future);
      }
    }

    test('findet ein Match aus einer gemeinsamen Gruppe, an dem der Freund beteiligt war', () async {
      await _seedGroup(firestore, 'g1', memberUids: ['alice', 'bob']);
      await _seedUserGroupIndex(firestore, 'alice', 'g1');
      await _seedMatch(firestore, 'g1', 100, DateTime(2026, 1, 1), memberUids: ['alice', 'bob']);

      await settle('bob', ['g1']);
      final result = container.read(pastMatchesWithFriendProvider('bob')).value ?? const [];

      expect(result.map((gm) => gm.match.movieId), [100]);
    });

    test('zeigt kein Match aus einer gemeinsamen Gruppe, an dem der Freund nicht beteiligt war', () async {
      await _seedGroup(firestore, 'g1', memberUids: ['alice', 'bob', 'carol']);
      await _seedUserGroupIndex(firestore, 'alice', 'g1');
      // Match nur zwischen alice und carol - bob war nicht beteiligt.
      await _seedMatch(firestore, 'g1', 100, DateTime(2026, 1, 1), memberUids: ['alice', 'carol']);

      await settle('bob', ['g1']);
      final result = container.read(pastMatchesWithFriendProvider('bob')).value ?? const [];

      expect(result, isEmpty);
    });

    test('schließt ein Match aus einer nicht gemeinsamen Gruppe aus', () async {
      // g2 ist NICHT gemeinsam (bob nicht Mitglied) - das Match dort darf im
      // Freundes-Profil von bob nicht auftauchen, selbst wenn es
      // `member_uids: [alice, bob]` fälschlich enthielte.
      await _seedGroup(firestore, 'g2', memberUids: ['alice', 'carol']);
      await _seedUserGroupIndex(firestore, 'alice', 'g2');
      await _seedMatch(firestore, 'g2', 200, DateTime(2026, 1, 1), memberUids: ['alice', 'bob']);

      await settle('bob', ['g2']);
      final result = container.read(pastMatchesWithFriendProvider('bob')).value ?? const [];

      expect(result, isEmpty);
    });

    test('kombiniert Matches aus mehreren gemeinsamen Gruppen, neueste zuerst', () async {
      await _seedGroup(firestore, 'g1', memberUids: ['alice', 'bob']);
      await _seedGroup(firestore, 'g3', memberUids: ['alice', 'bob']);
      await _seedUserGroupIndex(firestore, 'alice', 'g1');
      await _seedUserGroupIndex(firestore, 'alice', 'g3');
      await _seedMatch(firestore, 'g1', 100, DateTime(2026, 1, 1), memberUids: ['alice', 'bob']);
      await _seedMatch(firestore, 'g3', 300, DateTime(2026, 1, 10), memberUids: ['alice', 'bob']);

      await settle('bob', ['g1', 'g3']);
      final result = container.read(pastMatchesWithFriendProvider('bob')).value ?? const [];

      expect(result.map((gm) => gm.match.movieId).toList(), [300, 100]);
    });
  });
}
