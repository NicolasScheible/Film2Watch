import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:film2watch/components/movies/swipe_card.dart';
import 'package:film2watch/providers/auth_provider.dart';
import 'package:film2watch/providers/tmdb_provider.dart';
import 'package:film2watch/repositories/group_repository.dart';
import 'package:film2watch/screens/groups/group_swipe_screen.dart';
import 'package:film2watch/screens/movies/movie_detail_screen.dart';
import 'package:film2watch/services/tmdb_service.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> _discoverJson(int id, String title) => {
      'id': id,
      'title': title,
      'genre_ids': <int>[],
    };

TmdbService _tmdbService(Map<int, String> movies) {
  final client = MockClient((request) async {
    if (request.url.path.contains('/genre/movie/list')) {
      return http.Response(jsonEncode({'genres': <dynamic>[]}), 200);
    }
    if (request.url.path.contains('/watch/providers')) {
      return http.Response(jsonEncode({'results': <String, dynamic>{}}), 200);
    }
    if (request.url.path.contains('/discover/movie')) {
      final page = int.parse(request.url.queryParameters['page'] ?? '1');
      final results =
          page == 1 ? movies.entries.map((e) => _discoverJson(e.key, e.value)).toList() : <dynamic>[];
      return http.Response(
        jsonEncode({'page': page, 'total_pages': 1, 'total_results': movies.length, 'results': results}),
        200,
      );
    }
    if (request.url.path.contains('/videos')) {
      return http.Response(jsonEncode({'results': <dynamic>[]}), 200);
    }
    final match = RegExp(r'/movie/(\d+)$').firstMatch(request.url.path);
    if (match != null) {
      final id = int.parse(match.group(1)!);
      return http.Response(
        jsonEncode({'id': id, 'title': movies[id], 'genres': <dynamic>[], 'overview': ''}),
        200,
      );
    }
    return http.Response('{}', 404);
  });
  return TmdbService(client, accessToken: 'test-token');
}

Future<ProviderContainer> _readyContainer({
  required FakeFirebaseFirestore firestore,
  required MockFirebaseAuth auth,
  required TmdbService tmdbService,
}) async {
  final container = ProviderContainer(
    overrides: [
      firebaseAuthProvider.overrideWithValue(auth),
      firestoreProvider.overrideWithValue(firestore),
      tmdbServiceProvider.overrideWithValue(tmdbService),
    ],
  );
  container.listen(authStateChangesProvider, (previous, next) {});
  await container.read(authStateChangesProvider.future);
  return container;
}

void main() {
  group('GroupSwipeScreen - Antippen der Filmkarte öffnet die Filmdetails (§9 Trailer-Erreichbarkeit)', () {
    late FakeFirebaseFirestore firestore;
    late MockFirebaseAuth auth;
    late String groupId;

    setUp(() async {
      firestore = FakeFirebaseFirestore();
      auth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'alice', email: 'alice@film2watch.app'),
        signedIn: true,
      );
      final group = await GroupRepository(firestore).createGroup(name: 'Filmabend', creatorUid: 'alice');
      groupId = group.id;
    });

    testWidgets('ein reines Antippen (ohne Ziehen) der Karte öffnet MovieDetailScreen für den angezeigten Film',
        (tester) async {
      final container = await _readyContainer(
        firestore: firestore,
        auth: auth,
        tmdbService: _tmdbService({300: 'Film A', 301: 'Film B'}),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: GroupSwipeScreen(groupId: groupId)),
        ),
      );
      await tester.pumpAndSettle();

      final filmAShownFirst = find.text('Film A').evaluate().isNotEmpty;
      final shownTitle = filmAShownFirst ? 'Film A' : 'Film B';

      await tester.tap(find.byType(SwipeCard));
      await tester.pumpAndSettle();

      expect(find.byType(MovieDetailScreen), findsOneWidget);
      expect(find.text(shownTitle), findsOneWidget);
    });

    testWidgets('ein tatsächliches Ziehen über die Wisch-Schwelle öffnet NICHT die Filmdetails, sondern löst den Swipe aus',
        (tester) async {
      final container = await _readyContainer(
        firestore: firestore,
        auth: auth,
        tmdbService: _tmdbService({310: 'Film C', 311: 'Film D'}),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: GroupSwipeScreen(groupId: groupId)),
        ),
      );
      await tester.pumpAndSettle();

      final filmCShownFirst = find.text('Film C').evaluate().isNotEmpty;
      final shownId = filmCShownFirst ? 310 : 311;

      await tester.drag(find.byType(GroupSwipeScreen).hitTestable(), const Offset(300, 0));
      await tester.pumpAndSettle();

      expect(find.byType(MovieDetailScreen), findsNothing);
      final swipeDoc = await firestore
          .collection('groups')
          .doc(groupId)
          .collection('swipes')
          .doc('alice_$shownId')
          .get();
      expect(swipeDoc.data()!['decision'], 'like');
    });

    testWidgets('von der Filmdetails-Seite aus ist der Trailer-Button während des Swipens erreichbar',
        (tester) async {
      final container = await _readyContainer(
        firestore: firestore,
        auth: auth,
        tmdbService: TmdbService(
          MockClient((request) async {
            if (request.url.path.contains('/genre/movie/list')) {
              return http.Response(jsonEncode({'genres': <dynamic>[]}), 200);
            }
            if (request.url.path.contains('/watch/providers')) {
              return http.Response(jsonEncode({'results': <String, dynamic>{}}), 200);
            }
            if (request.url.path.contains('/discover/movie')) {
              final page = int.parse(request.url.queryParameters['page'] ?? '1');
              final results = page == 1 ? [_discoverJson(320, 'Film E')] : <dynamic>[];
              return http.Response(
                jsonEncode({'page': page, 'total_pages': 1, 'total_results': 1, 'results': results}),
                200,
              );
            }
            if (request.url.path.contains('/videos')) {
              return http.Response(
                jsonEncode({
                  'results': [
                    {
                      'key': 'abc123',
                      'site': 'YouTube',
                      'type': 'Trailer',
                      'official': true,
                      'published_at': '2020-01-01T00:00:00Z',
                      'name': 'Official Trailer',
                    },
                  ],
                }),
                200,
              );
            }
            if (RegExp(r'/movie/(\d+)$').hasMatch(request.url.path)) {
              return http.Response(
                jsonEncode({'id': 320, 'title': 'Film E', 'genres': <dynamic>[], 'overview': ''}),
                200,
              );
            }
            return http.Response('{}', 404);
          }),
          accessToken: 'test-token',
        ),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: GroupSwipeScreen(groupId: groupId)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(SwipeCard));
      await tester.pumpAndSettle();

      expect(find.text('Trailer ansehen'), findsOneWidget);
    });
  });
}
