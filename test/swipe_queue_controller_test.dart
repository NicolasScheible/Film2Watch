import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:film2watch/models/movie_swipe.dart';
import 'package:film2watch/providers/auth_provider.dart';
import 'package:film2watch/providers/swipe_queue_controller.dart';
import 'package:film2watch/providers/tmdb_provider.dart';
import 'package:film2watch/services/tmdb_service.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> _movieJson(int id) => {
      'id': id,
      'title': 'Film $id',
      'genre_ids': <int>[],
    };

/// Baut einen TmdbService, dessen `/discover/movie`-Antworten von [pages]
/// abhängen (Seite -> Filme dieser Seite). Löst nie echte HTTP-Requests aus.
TmdbService _tmdbServiceForPages(Map<int, List<int>> pages, {required int totalPages}) {
  final client = MockClient((request) async {
    if (request.url.path.contains('/genre/movie/list')) {
      return http.Response(jsonEncode({'genres': <dynamic>[]}), 200);
    }
    if (request.url.path.contains('/discover/movie')) {
      final page = int.parse(request.url.queryParameters['page'] ?? '1');
      final ids = pages[page] ?? const <int>[];
      return http.Response(
        jsonEncode({
          'page': page,
          'total_pages': totalPages,
          'total_results': totalPages * 20,
          'results': ids.map(_movieJson).toList(),
        }),
        200,
      );
    }
    return http.Response('{}', 404);
  });
  return TmdbService(client, accessToken: 'test-token');
}

ProviderContainer _buildContainer({
  required FakeFirebaseFirestore firestore,
  required TmdbService tmdbService,
}) {
  final auth = MockFirebaseAuth(
    mockUser: MockUser(uid: 'alice', email: 'alice@film2watch.app'),
    signedIn: true,
  );
  final container = ProviderContainer(
    overrides: [
      firebaseAuthProvider.overrideWithValue(auth),
      firestoreProvider.overrideWithValue(firestore),
      tmdbServiceProvider.overrideWithValue(tmdbService),
    ],
  );
  // MockFirebaseAuth feuert sein initiales Sign-in-Event auf einem
  // Broadcast-Stream ohne Replay - der Listener muss deshalb im selben
  // synchronen Abschnitt registriert werden, noch vor jedem `await`.
  container.listen(authStateChangesProvider, (previous, next) {});
  return container;
}

void main() {
  group('SwipeQueueController', () {
    test('bereits bewertete Filme werden aus der Warteschlange ausgeblendet', () async {
      final firestore = FakeFirebaseFirestore();
      final now = DateTime.now();
      await firestore
          .collection('groups')
          .doc('g1')
          .collection('swipes')
          .doc('alice_1')
          .set(MovieSwipe(
            uid: 'alice',
            movieId: 1,
            decision: SwipeDecision.like,
            createdAt: now,
            updatedAt: now,
          ).toFirestore());

      final tmdbService = _tmdbServiceForPages({1: [1, 2, 3]}, totalPages: 1);
      final container = _buildContainer(firestore: firestore, tmdbService: tmdbService);
      addTearDown(container.dispose);
      await container.read(authStateChangesProvider.future);

      final queue = await container.read(swipeQueueControllerProvider('g1').future);

      expect(queue.map((m) => m.tmdbId), containsAll([2, 3]));
      expect(queue.map((m) => m.tmdbId), isNot(contains(1)));
    });

    test('leere Warteschlange, wenn TMDB keine weiteren Filme mehr liefert', () async {
      final firestore = FakeFirebaseFirestore();
      final tmdbService = _tmdbServiceForPages({1: []}, totalPages: 1);
      final container = _buildContainer(firestore: firestore, tmdbService: tmdbService);
      addTearDown(container.dispose);
      await container.read(authStateChangesProvider.future);

      final queue = await container.read(swipeQueueControllerProvider('g1').future);

      expect(queue, isEmpty);
    });

    test('lädt bei Bedarf mehrere TMDB-Seiten nach (Pagination)', () async {
      final firestore = FakeFirebaseFirestore();
      final tmdbService = _tmdbServiceForPages(
        {
          1: [1, 2, 3, 4],
          2: [5, 6, 7, 8],
          3: [9, 10, 11, 12],
        },
        totalPages: 5,
      );
      final container = _buildContainer(firestore: firestore, tmdbService: tmdbService);
      addTearDown(container.dispose);
      await container.read(authStateChangesProvider.future);

      final queue = await container.read(swipeQueueControllerProvider('g1').future);

      expect(queue.length, greaterThanOrEqualTo(10));
      expect(queue.map((m) => m.tmdbId).toSet().length, queue.length);
    });
  });
}
