import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:film2watch/models/movie_night.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MovieNight (§12: "Filmabend planen")', () {
    test('fromFirestore mappt alle Felder korrekt', () async {
      final firestore = FakeFirebaseFirestore();
      final scheduledAt = DateTime(2026, 12, 24, 20, 0);
      final ref = firestore.collection('groups').doc('g1').collection('movie_nights').doc('mn1');
      await ref.set({
        'created_by': 'alice',
        'created_at': Timestamp.now(),
        'updated_at': Timestamp.now(),
        'scheduled_at': Timestamp.fromDate(scheduledAt),
        'platform_id': 8,
        'movie_id': 550,
      });

      final doc = await ref.get();
      final movieNight = MovieNight.fromFirestore(doc);

      expect(movieNight.id, 'mn1');
      expect(movieNight.createdBy, 'alice');
      expect(movieNight.scheduledAt, scheduledAt);
      expect(movieNight.platformId, 8);
      expect(movieNight.movieId, 550);
    });

    test('fromFirestore liest ein Dokument ohne movie_id als null (kein Pflichtfeld)', () async {
      final firestore = FakeFirebaseFirestore();
      final ref = firestore.collection('groups').doc('g1').collection('movie_nights').doc('mn2');
      await ref.set({
        'created_by': 'alice',
        'created_at': Timestamp.now(),
        'updated_at': Timestamp.now(),
        'scheduled_at': Timestamp.now(),
        'platform_id': 8,
      });

      final doc = await ref.get();
      final movieNight = MovieNight.fromFirestore(doc);

      expect(movieNight.movieId, isNull);
    });

    test('toFirestoreCreate setzt created_at/updated_at über FieldValue.serverTimestamp()', () {
      final data = MovieNight.toFirestoreCreate(
        createdBy: 'alice',
        scheduledAt: DateTime(2026, 1, 1, 20),
        platformId: 8,
      );

      expect(data['created_by'], 'alice');
      expect(data['created_at'], isA<FieldValue>());
      expect(data['updated_at'], isA<FieldValue>());
      expect(data.containsKey('movie_id'), isFalse);
    });

    test('toFirestoreCreate setzt movie_id nur, wenn angegeben', () {
      final data = MovieNight.toFirestoreCreate(
        createdBy: 'alice',
        scheduledAt: DateTime(2026, 1, 1, 20),
        platformId: 8,
        movieId: 550,
      );

      expect(data['movie_id'], 550);
    });

    test('toFirestoreUpdate enthält weder created_by noch created_at (unveränderlich)', () {
      final data = MovieNight.toFirestoreUpdate(
        scheduledAt: DateTime(2026, 1, 1, 20),
        platformId: 8,
      );

      expect(data.containsKey('created_by'), isFalse);
      expect(data.containsKey('created_at'), isFalse);
      expect(data['updated_at'], isA<FieldValue>());
    });

    test('toFirestoreUpdate löscht movie_id (FieldValue.delete()), wenn kein Film mehr angegeben ist', () {
      final data = MovieNight.toFirestoreUpdate(
        scheduledAt: DateTime(2026, 1, 1, 20),
        platformId: 8,
      );

      expect(data['movie_id'], FieldValue.delete());
    });

    test('toFirestoreUpdate setzt movie_id, wenn ein Film angegeben ist', () {
      final data = MovieNight.toFirestoreUpdate(
        scheduledAt: DateTime(2026, 1, 1, 20),
        platformId: 8,
        movieId: 550,
      );

      expect(data['movie_id'], 550);
    });
  });
}
