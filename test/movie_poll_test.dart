import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:film2watch/models/movie_poll.dart';
import 'package:film2watch/models/movie_poll_option.dart';
import 'package:film2watch/models/movie_poll_vote.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MoviePoll', () {
    late FakeFirebaseFirestore firestore;

    setUp(() {
      firestore = FakeFirebaseFirestore();
    });

    test('toFirestoreCreate/fromFirestore Roundtrip mit status "open"', () async {
      final deadline = DateTime(2027, 1, 1, 20);
      final ref = await firestore
          .collection('polls')
          .add(MoviePoll.toFirestoreCreate(createdBy: 'alice', deadline: deadline));
      final snapshot = await ref.get();

      final poll = MoviePoll.fromFirestore(snapshot);

      expect(poll.createdBy, 'alice');
      expect(poll.deadline, deadline);
      expect(poll.status, 'open');
      expect(poll.isOpen, isTrue);
      expect(poll.winningOptionId, isNull);
      expect(poll.resultMovieNightId, isNull);
      expect(poll.resolvedAt, isNull);
    });

    test('isOpen ist false, sobald status "closed" ist', () async {
      final ref = await firestore.collection('polls').add({
        'created_by': 'alice',
        'created_at': Timestamp.now(),
        'deadline': Timestamp.now(),
        'status': 'closed',
        'winning_option_id': 'opt1',
        'result_movie_night_id': 'mn1',
        'resolved_at': Timestamp.now(),
      });
      final snapshot = await ref.get();

      final poll = MoviePoll.fromFirestore(snapshot);

      expect(poll.isOpen, isFalse);
      expect(poll.winningOptionId, 'opt1');
      expect(poll.resultMovieNightId, 'mn1');
      expect(poll.resolvedAt, isNotNull);
    });
  });

  group('MoviePollOption', () {
    late FakeFirebaseFirestore firestore;

    setUp(() {
      firestore = FakeFirebaseFirestore();
    });

    test('toFirestoreCreate/fromFirestore Roundtrip ohne movieId', () async {
      final scheduledAt = DateTime(2027, 1, 1, 20);
      final ref = await firestore.collection('options').add(
            MoviePollOption.toFirestoreCreate(scheduledAt: scheduledAt, platformId: 8),
          );
      final snapshot = await ref.get();

      final option = MoviePollOption.fromFirestore(snapshot);

      expect(option.scheduledAt, scheduledAt);
      expect(option.platformId, 8);
      expect(option.movieId, isNull);
    });

    test('toFirestoreCreate/fromFirestore Roundtrip mit movieId', () async {
      final scheduledAt = DateTime(2027, 1, 1, 20);
      final ref = await firestore.collection('options').add(
            MoviePollOption.toFirestoreCreate(scheduledAt: scheduledAt, platformId: 8, movieId: 550),
          );
      final snapshot = await ref.get();

      final option = MoviePollOption.fromFirestore(snapshot);

      expect(option.movieId, 550);
    });
  });

  group('MoviePollVote', () {
    test('idFor ist deterministisch aus uid und optionId', () {
      expect(MoviePollVote.idFor(uid: 'alice', optionId: 'opt1'), 'alice_opt1');
    });

    test('toFirestoreCreate/fromFirestore Roundtrip', () async {
      final firestore = FakeFirebaseFirestore();
      final voteId = MoviePollVote.idFor(uid: 'alice', optionId: 'opt1');
      await firestore
          .collection('votes')
          .doc(voteId)
          .set(MoviePollVote.toFirestoreCreate(uid: 'alice', optionId: 'opt1'));
      final snapshot = await firestore.collection('votes').doc(voteId).get();

      final vote = MoviePollVote.fromFirestore(snapshot);

      expect(vote.id, voteId);
      expect(vote.uid, 'alice');
      expect(vote.optionId, 'opt1');
    });
  });
}
