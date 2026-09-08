import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:film2watch/providers/auth_provider.dart';
import 'package:film2watch/providers/group_provider.dart';
import 'package:film2watch/providers/movie_poll_action_controller.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MoviePollActionController', () {
    late FakeFirebaseFirestore firestore;
    late ProviderContainer container;
    late String groupId;

    List<({DateTime scheduledAt, int platformId, int? movieId})> twoOptions() => [
          (scheduledAt: DateTime(2027, 1, 1, 20), platformId: 8, movieId: null),
          (scheduledAt: DateTime(2027, 1, 2, 20), platformId: 9, movieId: null),
        ];

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
      await container.read(moviePollActionControllerProvider(groupId).future);
    });

    Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> polls() async {
      final snapshot =
          await firestore.collection('groups').doc(groupId).collection('movie_night_polls').get();
      return snapshot.docs;
    }

    test('Status durchläuft Loading, bevor er im Erfolg landet', () async {
      final states = <bool>[];
      container.listen(
        moviePollActionControllerProvider(groupId),
        (previous, next) => states.add(next.isLoading),
        fireImmediately: true,
      );

      await container.read(moviePollActionControllerProvider(groupId).notifier).create(
            deadline: DateTime.now().add(const Duration(days: 7)),
            options: twoOptions(),
          );

      expect(states, contains(true));
      expect(states.last, isFalse);
    });

    test('create() landet im Erfolg und legt eine Abstimmung mit Optionen an', () async {
      final notifier = container.read(moviePollActionControllerProvider(groupId).notifier);

      await notifier.create(deadline: DateTime.now().add(const Duration(days: 7)), options: twoOptions());

      expect(container.read(moviePollActionControllerProvider(groupId)).hasError, isFalse);
      final createdPolls = await polls();
      expect(createdPolls, hasLength(1));
      final options = await firestore
          .collection('groups')
          .doc(groupId)
          .collection('movie_night_polls')
          .doc(createdPolls.first.id)
          .collection('options')
          .get();
      expect(options.docs, hasLength(2));
    });

    test('create() landet im Error, wenn weniger als zwei Terminvorschläge angegeben werden', () async {
      final notifier = container.read(moviePollActionControllerProvider(groupId).notifier);

      await notifier.create(
        deadline: DateTime.now().add(const Duration(days: 7)),
        options: [twoOptions().first],
      );

      expect(container.read(moviePollActionControllerProvider(groupId)).hasError, isTrue);
      expect(await polls(), isEmpty);
    });

    test('vote() gibt mehrere Stimmen für dieselbe Abstimmung ab', () async {
      final notifier = container.read(moviePollActionControllerProvider(groupId).notifier);
      await notifier.create(deadline: DateTime.now().add(const Duration(days: 7)), options: twoOptions());
      final pollId = (await polls()).first.id;
      final optionDocs = await firestore
          .collection('groups')
          .doc(groupId)
          .collection('movie_night_polls')
          .doc(pollId)
          .collection('options')
          .get();
      final optionIds = optionDocs.docs.map((d) => d.id).toSet();

      await notifier.vote(pollId: pollId, optionIds: optionIds);

      expect(container.read(moviePollActionControllerProvider(groupId)).hasError, isFalse);
      final votes = await firestore
          .collection('groups')
          .doc(groupId)
          .collection('movie_night_polls')
          .doc(pollId)
          .collection('votes')
          .get();
      expect(votes.docs, hasLength(2));
    });
  });
}
