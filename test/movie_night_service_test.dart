import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:film2watch/repositories/group_repository.dart';
import 'package:film2watch/repositories/match_repository.dart';
import 'package:film2watch/repositories/movie_night_repository.dart';
import 'package:film2watch/services/movie_night_service.dart';
import 'package:film2watch/utils/movie_night_exceptions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MovieNightService (§12: "Filmabend planen")', () {
    late FakeFirebaseFirestore firestore;
    late MovieNightService service;
    late String groupId;

    setUp(() async {
      firestore = FakeFirebaseFirestore();
      service = MovieNightService(
        MovieNightRepository(firestore),
        GroupRepository(firestore),
        MatchRepository(firestore),
      );
      final group = await GroupRepository(firestore).createGroup(name: 'Filmabend', creatorUid: 'alice');
      groupId = group.id;
      // bob als normales Mitglied hinzufügen.
      await firestore
          .collection('groups')
          .doc(groupId)
          .collection('members')
          .doc('bob')
          .set({'uid': 'bob', 'role': 'member', 'joined_at': Timestamp.now()});
      // Ein Match dieser Gruppe.
      await firestore.collection('groups').doc(groupId).collection('matches').doc('550').set({
        'movie_id': 550,
        'member_uids': ['alice', 'bob'],
        'matched_at': Timestamp.now(),
      });
    });

    Future<QuerySnapshot<Map<String, dynamic>>> movieNights() {
      return firestore.collection('groups').doc(groupId).collection('movie_nights').get();
    }

    group('createMovieNight', () {
      test('ein Mitglied kann einen Filmabend anlegen', () async {
        await service.createMovieNight(
          groupId: groupId,
          uid: 'bob',
          scheduledAt: DateTime(2026, 12, 24, 20),
          platformId: 8,
        );

        final docs = (await movieNights()).docs;
        expect(docs, hasLength(1));
        expect(docs.first.data()['created_by'], 'bob');
      });

      test('ein Nicht-Mitglied kann keinen Filmabend anlegen', () async {
        await expectLater(
          service.createMovieNight(
            groupId: groupId,
            uid: 'carol',
            scheduledAt: DateTime(2026, 12, 24, 20),
            platformId: 8,
          ),
          throwsA(isA<MovieNightActionException>()),
        );
      });

      test('ein Film kann angegeben werden, wenn er ein bestehendes Match ist', () async {
        await service.createMovieNight(
          groupId: groupId,
          uid: 'alice',
          scheduledAt: DateTime(2026, 12, 24, 20),
          platformId: 8,
          movieId: 550,
        );

        final docs = (await movieNights()).docs;
        expect(docs.first.data()['movie_id'], 550);
      });

      test('ein Film, der kein Match der Gruppe ist, wird abgelehnt', () async {
        await expectLater(
          service.createMovieNight(
            groupId: groupId,
            uid: 'alice',
            scheduledAt: DateTime(2026, 12, 24, 20),
            platformId: 8,
            movieId: 999,
          ),
          throwsA(isA<MovieNightActionException>()),
        );
        expect((await movieNights()).docs, isEmpty);
      });

      test('ganz ohne Film ist weiterhin erlaubt', () async {
        await service.createMovieNight(
          groupId: groupId,
          uid: 'alice',
          scheduledAt: DateTime(2026, 12, 24, 20),
          platformId: 8,
        );

        expect((await movieNights()).docs, hasLength(1));
      });
    });

    group('updateMovieNight (Bearbeiten)', () {
      Future<String> createAsBob() async {
        await service.createMovieNight(
          groupId: groupId,
          uid: 'bob',
          scheduledAt: DateTime(2026, 12, 24, 20),
          platformId: 8,
        );
        return (await movieNights()).docs.first.id;
      }

      test('der Ersteller darf den eigenen Filmabend bearbeiten', () async {
        final id = await createAsBob();

        await service.updateMovieNight(
          groupId: groupId,
          uid: 'bob',
          movieNightId: id,
          scheduledAt: DateTime(2027, 1, 1, 20),
          platformId: 9,
        );

        final doc = await firestore.collection('groups').doc(groupId).collection('movie_nights').doc(id).get();
        expect(doc.data()!['platform_id'], 9);
      });

      test('der Gruppen-Admin darf einen fremden Filmabend bearbeiten', () async {
        final id = await createAsBob();

        await service.updateMovieNight(
          groupId: groupId,
          uid: 'alice',
          movieNightId: id,
          scheduledAt: DateTime(2027, 1, 1, 20),
          platformId: 9,
        );

        final doc = await firestore.collection('groups').doc(groupId).collection('movie_nights').doc(id).get();
        expect(doc.data()!['platform_id'], 9);
      });

      test('ein normales, fremdes Mitglied darf den Filmabend eines anderen nicht bearbeiten', () async {
        await firestore
            .collection('groups')
            .doc(groupId)
            .collection('members')
            .doc('carol')
            .set({'uid': 'carol', 'role': 'member', 'joined_at': Timestamp.now()});
        final id = await createAsBob();

        await expectLater(
          service.updateMovieNight(
            groupId: groupId,
            uid: 'carol',
            movieNightId: id,
            scheduledAt: DateTime(2027, 1, 1, 20),
            platformId: 9,
          ),
          throwsA(isA<MovieNightActionException>()),
        );
      });

      test('ein Update mit einem Film, der kein Match ist, wird abgelehnt', () async {
        final id = await createAsBob();

        await expectLater(
          service.updateMovieNight(
            groupId: groupId,
            uid: 'bob',
            movieNightId: id,
            scheduledAt: DateTime(2027, 1, 1, 20),
            platformId: 9,
            movieId: 999,
          ),
          throwsA(isA<MovieNightActionException>()),
        );
      });

      test('ein Update eines nicht mehr existierenden Filmabends wirft eine verständliche Exception', () async {
        await expectLater(
          service.updateMovieNight(
            groupId: groupId,
            uid: 'bob',
            movieNightId: 'does-not-exist',
            scheduledAt: DateTime(2027, 1, 1, 20),
            platformId: 9,
          ),
          throwsA(isA<MovieNightActionException>()),
        );
      });
    });

    group('cancelMovieNight (Absagen/Löschen)', () {
      Future<String> createAsBob() async {
        await service.createMovieNight(
          groupId: groupId,
          uid: 'bob',
          scheduledAt: DateTime(2026, 12, 24, 20),
          platformId: 8,
        );
        return (await movieNights()).docs.first.id;
      }

      test('der Ersteller darf den eigenen Filmabend absagen', () async {
        final id = await createAsBob();

        await service.cancelMovieNight(groupId: groupId, uid: 'bob', movieNightId: id);

        expect((await movieNights()).docs, isEmpty);
      });

      test('der Gruppen-Admin darf einen fremden Filmabend absagen', () async {
        final id = await createAsBob();

        await service.cancelMovieNight(groupId: groupId, uid: 'alice', movieNightId: id);

        expect((await movieNights()).docs, isEmpty);
      });

      test('ein normales, fremdes Mitglied darf einen fremden Filmabend nicht absagen', () async {
        await firestore
            .collection('groups')
            .doc(groupId)
            .collection('members')
            .doc('carol')
            .set({'uid': 'carol', 'role': 'member', 'joined_at': Timestamp.now()});
        final id = await createAsBob();

        await expectLater(
          service.cancelMovieNight(groupId: groupId, uid: 'carol', movieNightId: id),
          throwsA(isA<MovieNightActionException>()),
        );
        expect((await movieNights()).docs, hasLength(1));
      });
    });
  });
}
