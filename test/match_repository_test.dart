import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:film2watch/models/movie_match.dart';
import 'package:film2watch/repositories/match_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MovieMatch', () {
    test('Firestore-Mapping liest alle Felder korrekt', () async {
      final firestore = FakeFirebaseFirestore();
      final matchedAt = DateTime(2026, 1, 1, 12);
      final ref = firestore.collection('groups').doc('g1').collection('matches').doc('550');
      await ref.set({
        'movie_id': 550,
        'member_uids': ['alice', 'bob', 'carol'],
        'matched_at': Timestamp.fromDate(matchedAt),
      });

      final match = MovieMatch.fromFirestore(await ref.get());

      expect(match.movieId, 550);
      expect(match.memberUids, ['alice', 'bob', 'carol']);
      expect(match.matchedAt, matchedAt);
    });
  });

  group('MatchRepository', () {
    late FakeFirebaseFirestore firestore;
    late MatchRepository repository;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      repository = MatchRepository(firestore);
    });

    Future<void> seedMatch(String groupId, int movieId, DateTime matchedAt) {
      return firestore.collection('groups').doc(groupId).collection('matches').doc('$movieId').set({
        'movie_id': movieId,
        'member_uids': ['alice', 'bob'],
        'matched_at': Timestamp.fromDate(matchedAt),
      });
    }

    test('liefert eine leere Liste, wenn keine Matches existieren', () async {
      final matches = await repository.watchMatches('g1').first;
      expect(matches, isEmpty);
    });

    test('liefert bestehende Matches, neueste zuerst', () async {
      await seedMatch('g1', 100, DateTime(2026, 1, 1));
      await seedMatch('g1', 200, DateTime(2026, 1, 5));

      final matches = await repository.watchMatches('g1').first;

      expect(matches.map((m) => m.movieId).toList(), [200, 100]);
    });

    test('reagiert in Echtzeit auf ein neu hinzugefügtes Match', () async {
      final emissions = <List<MovieMatch>>[];
      final subscription = repository.watchMatches('g1').listen(emissions.add);
      addTearDown(subscription.cancel);
      await Future.delayed(Duration.zero);
      expect(emissions.first, isEmpty);

      await seedMatch('g1', 300, DateTime.now());
      await Future.delayed(Duration.zero);

      expect(emissions.last.map((m) => m.movieId), contains(300));
    });

    test('Matches verschiedener Gruppen sind unabhängig voneinander', () async {
      await seedMatch('g1', 1, DateTime.now());
      await seedMatch('g2', 2, DateTime.now());

      final g1Matches = await repository.watchMatches('g1').first;
      final g2Matches = await repository.watchMatches('g2').first;

      expect(g1Matches.map((m) => m.movieId), [1]);
      expect(g2Matches.map((m) => m.movieId), [2]);
    });
  });
}
