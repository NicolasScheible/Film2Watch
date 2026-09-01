import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:film2watch/providers/auth_provider.dart';
import 'package:film2watch/providers/group_provider.dart';
import 'package:film2watch/providers/movie_night_action_controller.dart';
import 'package:film2watch/providers/movie_night_provider.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MovieNightActionController', () {
    late FakeFirebaseFirestore firestore;
    late ProviderContainer container;
    late String groupId;

    setUp(() async {
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
      await container.read(authStateChangesProvider.future);

      final group = await container.read(groupRepositoryProvider).createGroup(
            name: 'Filmabend',
            creatorUid: 'alice',
          );
      groupId = group.id;
      await container.read(movieNightActionControllerProvider(groupId).future);
    });

    Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> movieNights() async {
      final snapshot =
          await firestore.collection('groups').doc(groupId).collection('movie_nights').get();
      return snapshot.docs;
    }

    test('Status durchläuft Loading, bevor er im Erfolg landet', () async {
      final states = <bool>[];
      container.listen(
        movieNightActionControllerProvider(groupId),
        (previous, next) => states.add(next.isLoading),
        fireImmediately: true,
      );

      await container.read(movieNightActionControllerProvider(groupId).notifier).create(
            scheduledAt: DateTime(2026, 12, 24, 20),
            platformId: 8,
          );

      expect(states, contains(true));
      expect(states.last, isFalse);
    });

    test('create() landet im Erfolg und legt ein Dokument an', () async {
      final notifier = container.read(movieNightActionControllerProvider(groupId).notifier);

      await notifier.create(scheduledAt: DateTime(2026, 12, 24, 20), platformId: 8);

      expect(container.read(movieNightActionControllerProvider(groupId)).hasError, isFalse);
      expect(await movieNights(), hasLength(1));
    });

    test('create() landet im Error, wenn der User kein Mitglied ist (Nicht-Mitglied)', () async {
      final foreignAuth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'carol', email: 'carol@film2watch.app'),
        signedIn: true,
      );
      final foreignContainer = ProviderContainer(
        overrides: [
          firebaseAuthProvider.overrideWithValue(foreignAuth),
          firestoreProvider.overrideWithValue(firestore),
        ],
      );
      addTearDown(foreignContainer.dispose);
      foreignContainer.listen(authStateChangesProvider, (previous, next) {});
      await foreignContainer.read(authStateChangesProvider.future);
      await foreignContainer.read(movieNightActionControllerProvider(groupId).future);

      await foreignContainer
          .read(movieNightActionControllerProvider(groupId).notifier)
          .create(scheduledAt: DateTime(2026, 12, 24, 20), platformId: 8);

      expect(foreignContainer.read(movieNightActionControllerProvider(groupId)).hasError, isTrue);
    });

    test('mehrfaches schnelles Anlegen (Double-Submit) erzeugt nur einen einzigen Filmabend', () async {
      final notifier = container.read(movieNightActionControllerProvider(groupId).notifier);

      final first = notifier.create(scheduledAt: DateTime(2026, 12, 24, 20), platformId: 8);
      final second = notifier.create(scheduledAt: DateTime(2026, 12, 25, 20), platformId: 9);
      await Future.wait([first, second]);

      expect(await movieNights(), hasLength(1));
    });

    test('edit() aktualisiert einen bestehenden Filmabend', () async {
      final notifier = container.read(movieNightActionControllerProvider(groupId).notifier);
      await notifier.create(scheduledAt: DateTime(2026, 12, 24, 20), platformId: 8);
      final id = (await movieNights()).first.id;

      await notifier.edit(movieNightId: id, scheduledAt: DateTime(2027, 1, 1, 20), platformId: 9);

      final doc = await firestore.collection('groups').doc(groupId).collection('movie_nights').doc(id).get();
      expect(doc.data()!['platform_id'], 9);
    });

    test('cancel() entfernt den Filmabend vollständig', () async {
      final notifier = container.read(movieNightActionControllerProvider(groupId).notifier);
      await notifier.create(scheduledAt: DateTime(2026, 12, 24, 20), platformId: 8);
      final id = (await movieNights()).first.id;

      await notifier.cancel(id);

      expect(await movieNights(), isEmpty);
    });

    test('groupMovieNightsProvider liefert den neu angelegten Filmabend live', () async {
      // `container.listen` hält den StreamProvider aktiv - ein reines
      // `container.read(...future)` würde ihn (analog zu `friendUidsProvider`
      // in `swipe_queue_controller.dart`) während des Ladens wieder entsorgen.
      container.listen(groupMovieNightsProvider(groupId), (previous, next) {});
      final notifier = container.read(movieNightActionControllerProvider(groupId).notifier);

      await notifier.create(scheduledAt: DateTime(2026, 12, 24, 20), platformId: 8);
      final movieNights = await container.read(groupMovieNightsProvider(groupId).future);

      expect(movieNights, hasLength(1));
      expect(movieNights.first.platformId, 8);
    });
  });
}
