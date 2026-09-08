import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:film2watch/repositories/group_repository.dart';
import 'package:film2watch/repositories/match_repository.dart';
import 'package:film2watch/repositories/movie_poll_repository.dart';
import 'package:film2watch/services/movie_poll_service.dart';
import 'package:film2watch/utils/movie_poll_exceptions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MoviePollService (§21: "Filmabend-Abstimmung")', () {
    late FakeFirebaseFirestore firestore;
    late MoviePollService service;
    late MoviePollRepository pollRepository;
    late String groupId;

    List<({DateTime scheduledAt, int platformId, int? movieId})> twoOptions() => [
          (scheduledAt: DateTime(2027, 1, 1, 20), platformId: 8, movieId: null),
          (scheduledAt: DateTime(2027, 1, 2, 20), platformId: 9, movieId: null),
        ];

    setUp(() async {
      firestore = FakeFirebaseFirestore();
      pollRepository = MoviePollRepository(firestore);
      service = MoviePollService(
        pollRepository,
        GroupRepository(firestore),
        MatchRepository(firestore),
      );
      final group = await GroupRepository(firestore).createGroup(name: 'Filmabend', creatorUid: 'alice');
      groupId = group.id;
      await firestore
          .collection('groups')
          .doc(groupId)
          .collection('members')
          .doc('bob')
          .set({'uid': 'bob', 'role': 'member', 'joined_at': Timestamp.now()});
      await firestore.collection('groups').doc(groupId).collection('matches').doc('550').set({
        'movie_id': 550,
        'member_uids': ['alice', 'bob'],
        'matched_at': Timestamp.now(),
      });
    });

    group('createPoll', () {
      test('ein Mitglied kann eine Abstimmung mit mehreren Terminvorschlägen anlegen', () async {
        final pollId = await service.createPoll(
          groupId: groupId,
          uid: 'bob',
          deadline: DateTime.now().add(const Duration(days: 7)),
          options: twoOptions(),
        );

        final poll = await pollRepository.getPoll(groupId: groupId, pollId: pollId);
        final options = await pollRepository.getOptions(groupId: groupId, pollId: pollId);

        expect(poll, isNotNull);
        expect(poll!.createdBy, 'bob');
        expect(poll.isOpen, isTrue);
        expect(options, hasLength(2));
      });

      test('ein Nicht-Mitglied kann keine Abstimmung anlegen', () async {
        await expectLater(
          service.createPoll(
            groupId: groupId,
            uid: 'carol',
            deadline: DateTime.now().add(const Duration(days: 7)),
            options: twoOptions(),
          ),
          throwsA(isA<MoviePollActionException>()),
        );
      });

      test('eine Deadline in der Vergangenheit wird abgelehnt', () async {
        await expectLater(
          service.createPoll(
            groupId: groupId,
            uid: 'bob',
            deadline: DateTime.now().subtract(const Duration(days: 1)),
            options: twoOptions(),
          ),
          throwsA(isA<MoviePollActionException>()),
        );
      });

      test('weniger als zwei Terminvorschläge werden abgelehnt', () async {
        await expectLater(
          service.createPoll(
            groupId: groupId,
            uid: 'bob',
            deadline: DateTime.now().add(const Duration(days: 7)),
            options: [twoOptions().first],
          ),
          throwsA(isA<MoviePollActionException>()),
        );
      });

      test('ein Terminvorschlag mit einem Film, der kein Match ist, wird abgelehnt', () async {
        await expectLater(
          service.createPoll(
            groupId: groupId,
            uid: 'bob',
            deadline: DateTime.now().add(const Duration(days: 7)),
            options: [
              (scheduledAt: DateTime(2027, 1, 1, 20), platformId: 8, movieId: 999),
              (scheduledAt: DateTime(2027, 1, 2, 20), platformId: 9, movieId: null),
            ],
          ),
          throwsA(isA<MoviePollActionException>()),
        );
      });

      test('ein Terminvorschlag mit einem Film, der ein bestehendes Match ist, ist erlaubt', () async {
        final pollId = await service.createPoll(
          groupId: groupId,
          uid: 'bob',
          deadline: DateTime.now().add(const Duration(days: 7)),
          options: [
            (scheduledAt: DateTime(2027, 1, 1, 20), platformId: 8, movieId: 550),
            (scheduledAt: DateTime(2027, 1, 2, 20), platformId: 9, movieId: null),
          ],
        );

        final options = await pollRepository.getOptions(groupId: groupId, pollId: pollId);
        expect(options.map((o) => o.movieId), contains(550));
      });
    });

    group('vote', () {
      Future<String> createOpenPoll() {
        return service.createPoll(
          groupId: groupId,
          uid: 'alice',
          deadline: DateTime.now().add(const Duration(days: 7)),
          options: twoOptions(),
        );
      }

      test('ein Mitglied kann mehrere Terminvorschläge gleichzeitig wählen (Doodle-Prinzip)', () async {
        final pollId = await createOpenPoll();
        final options = await pollRepository.getOptions(groupId: groupId, pollId: pollId);
        final optionIds = options.map((o) => o.id).toSet();

        await service.vote(groupId: groupId, uid: 'bob', pollId: pollId, optionIds: optionIds);

        final votes = await firestore
            .collection('groups')
            .doc(groupId)
            .collection('movie_night_polls')
            .doc(pollId)
            .collection('votes')
            .get();
        expect(votes.docs, hasLength(2));
      });

      test('eine erneute Abstimmung ersetzt die bisherige Auswahl vollständig', () async {
        final pollId = await createOpenPoll();
        final options = await pollRepository.getOptions(groupId: groupId, pollId: pollId);
        final firstOptionId = options.first.id;
        final secondOptionId = options.last.id;

        await service.vote(groupId: groupId, uid: 'bob', pollId: pollId, optionIds: {firstOptionId, secondOptionId});
        await service.vote(groupId: groupId, uid: 'bob', pollId: pollId, optionIds: {secondOptionId});

        final votesCollection = firestore
            .collection('groups')
            .doc(groupId)
            .collection('movie_night_polls')
            .doc(pollId)
            .collection('votes');
        final votes = (await votesCollection.get()).docs;
        expect(votes, hasLength(1));
        expect(votes.first.data()['option_id'], secondOptionId);
      });

      test('ein Nicht-Mitglied kann nicht abstimmen', () async {
        final pollId = await createOpenPoll();
        final options = await pollRepository.getOptions(groupId: groupId, pollId: pollId);

        await expectLater(
          service.vote(groupId: groupId, uid: 'carol', pollId: pollId, optionIds: {options.first.id}),
          throwsA(isA<MoviePollActionException>()),
        );
      });

      test('eine bereits abgelaufene Abstimmung lehnt weitere Stimmen ab', () async {
        final pollId = await service.createPoll(
          groupId: groupId,
          uid: 'alice',
          deadline: DateTime.now().add(const Duration(seconds: 1)),
          options: twoOptions(),
        );
        final options = await pollRepository.getOptions(groupId: groupId, pollId: pollId);
        await Future<void>.delayed(const Duration(seconds: 2));

        await expectLater(
          service.vote(groupId: groupId, uid: 'bob', pollId: pollId, optionIds: {options.first.id}),
          throwsA(isA<MoviePollActionException>()),
        );
      });

      test('eine Option, die nicht zur Abstimmung gehört, wird abgelehnt', () async {
        final pollId = await createOpenPoll();

        await expectLater(
          service.vote(groupId: groupId, uid: 'bob', pollId: pollId, optionIds: {'does-not-exist'}),
          throwsA(isA<MoviePollActionException>()),
        );
      });
    });
  });
}
