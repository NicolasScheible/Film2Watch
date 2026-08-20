import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:film2watch/providers/auth_provider.dart';
import 'package:film2watch/providers/group_provider.dart';
import 'package:film2watch/providers/match_provider.dart';
import 'package:film2watch/repositories/group_repository.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _seedMatch(
  FakeFirebaseFirestore firestore,
  String groupId,
  int movieId,
  DateTime matchedAt, {
  List<String> memberUids = const ['alice'],
}) {
  return firestore.collection('groups').doc(groupId).collection('matches').doc('$movieId').set({
    'movie_id': movieId,
    'member_uids': memberUids,
    'matched_at': Timestamp.fromDate(matchedAt),
  });
}

void main() {
  group('allMyMatchesProvider', () {
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

    test('leer, wenn der User in keiner Gruppe ist', () async {
      await container.read(authStateChangesProvider.future);
      // `container.listen` etabliert die Subscription, auf der `.future`
      // aufbaut - ein reines `container.read(provider.future)` ohne aktiven
      // Listener liefert bei verketteten StreamProvidern sonst nie.
      container.listen(myGroupsProvider, (previous, next) {});
      await container.read(myGroupsProvider.future);
      final result = container.read(allMyMatchesProvider);
      expect(result.value, isEmpty);
    });

    test('kombiniert Matches aus mehreren Gruppen, neueste zuerst', () async {
      await container.read(authStateChangesProvider.future);
      final groupRepository = GroupRepository(firestore);
      final groupA = await groupRepository.createGroup(name: 'Gruppe A', creatorUid: 'alice');
      final groupB = await groupRepository.createGroup(name: 'Gruppe B', creatorUid: 'alice');

      await _seedMatch(firestore, groupA.id, 100, DateTime(2026, 1, 1));
      await _seedMatch(firestore, groupB.id, 200, DateTime(2026, 1, 5));

      // Jeder beteiligte Stream-Provider muss sein erstes Firestore-Snapshot
      // tatsächlich geliefert haben, bevor `allMyMatchesProvider` (der sie
      // nur per `ref.watch(...).value` liest, ohne selbst zu warten) einen
      // vollständigen Zustand sehen kann. `container.listen` etabliert dabei
      // die Subscription, auf der `.future` aufbaut.
      container.listen(myGroupsProvider, (previous, next) {});
      await container.read(myGroupsProvider.future);
      container.listen(groupMatchesProvider(groupA.id), (previous, next) {});
      container.listen(groupMatchesProvider(groupB.id), (previous, next) {});
      await container.read(groupMatchesProvider(groupA.id).future);
      await container.read(groupMatchesProvider(groupB.id).future);

      final result = container.read(allMyMatchesProvider).value ?? const [];
      expect(result.map((gm) => gm.match.movieId).toList(), [200, 100]);
      expect(result.map((gm) => gm.group.name).toSet(), {'Gruppe A', 'Gruppe B'});
    });
  });
}
