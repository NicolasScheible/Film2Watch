import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:film2watch/providers/auth_provider.dart';
import 'package:film2watch/providers/tmdb_provider.dart';
import 'package:film2watch/repositories/group_repository.dart';
import 'package:film2watch/screens/groups/group_swipe_screen.dart';
import 'package:film2watch/services/tmdb_service.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> _movieJson(int id, String title) => {
      'id': id,
      'title': title,
      'genre_ids': <int>[],
    };

/// Discover liefert exakt [movies] (id -> Titel) auf Seite 1, danach nichts
/// mehr - simuliert eine endliche TMDB-Ergebnismenge, ohne echte
/// HTTP-Requests auszulösen.
TmdbService _tmdbService(Map<int, String> movies) {
  final client = MockClient((request) async {
    if (request.url.path.contains('/genre/movie/list')) {
      return http.Response(jsonEncode({'genres': <dynamic>[]}), 200);
    }
    if (request.url.path.contains('/discover/movie')) {
      final page = int.parse(request.url.queryParameters['page'] ?? '1');
      final results = page == 1 ? movies.entries.map((e) => _movieJson(e.key, e.value)).toList() : <dynamic>[];
      return http.Response(
        jsonEncode({'page': page, 'total_pages': 1, 'total_results': movies.length, 'results': results}),
        200,
      );
    }
    return http.Response('{}', 404);
  });
  return TmdbService(client, accessToken: 'test-token');
}

/// Baut einen [ProviderContainer], dessen `authStateChangesProvider` bereits
/// aufgelöst ist, bevor der Screen gepumpt wird. `MockFirebaseAuth` feuert
/// sein initiales Sign-in-Event auf einem Broadcast-Stream ohne Replay, und
/// `SwipeQueueController.build()` liest `authStateChangesProvider` synchron
/// (`ref.read(...).value`, kein `.future`-Await) - ohne diese Vorwärmung
/// wäre der Uid beim allerersten Aufbau noch `null` und der Controller
/// bricht mit "benötigt einen eingeloggten User" ab, obwohl der User
/// tatsächlich eingeloggt ist. Betrifft nur die Testkonstruktion, nicht die
/// echte App (dort ist die Auth beim Erreichen des Swipe-Screens über
/// `AppGate` immer längst aufgelöst).
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
  group('GroupSwipeScreen - Skip', () {
    late FakeFirebaseFirestore firestore;
    late MockFirebaseAuth auth;
    late String groupId;

    setUp(() async {
      firestore = FakeFirebaseFirestore();
      auth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'alice', email: 'alice@film2watch.app'),
        signedIn: true,
      );
      final group = await GroupRepository(firestore).createGroup(
        name: 'Filmabend',
        creatorUid: 'alice',
      );
      groupId = group.id;
    });

    testWidgets('Skip-Button speichert decision == skip und zeigt danach die nächste Karte',
        (tester) async {
      final container = await _readyContainer(
        firestore: firestore,
        auth: auth,
        tmdbService: _tmdbService({100: 'Film A', 101: 'Film B'}),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: GroupSwipeScreen(groupId: groupId)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Film A'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.watch_later_outlined));
      await tester.pumpAndSettle();

      final swipeDoc = await firestore
          .collection('groups')
          .doc(groupId)
          .collection('swipes')
          .doc('alice_100')
          .get();
      expect(swipeDoc.data()!['decision'], 'skip');

      // Die nächste Karte (Film B) ist jetzt sichtbar, Film A verschwunden.
      expect(find.text('Film B'), findsOneWidget);
      expect(find.text('Film A'), findsNothing);
    });

    testWidgets('geskippter Film erscheint nicht erneut, wenn der Screen neu aufgebaut wird',
        (tester) async {
      final firstContainer = await _readyContainer(
        firestore: firestore,
        auth: auth,
        tmdbService: _tmdbService({200: 'Wird geskippt', 201: 'Bleibt übrig'}),
      );
      addTearDown(firstContainer.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: firstContainer,
          child: MaterialApp(home: GroupSwipeScreen(groupId: groupId)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.watch_later_outlined));
      await tester.pumpAndSettle();
      expect(find.text('Bleibt übrig'), findsOneWidget);

      // Ein komplett neuer Screen-/Provider-Aufbau, der den bereits in
      // Firestore gespeicherten Skip erneut einliest - der Film darf trotzdem
      // nicht wieder auftauchen. Eigene MockFirebaseAuth-Instanz (derselbe
      // User), weil `authStateChanges()` von firebase_auth_mocks ihr
      // einziges Event nur einmal pro Instanz liefert - ein zweiter
      // Container an derselben Instanz würde beim Warten auf das erste
      // Auth-Event für immer hängen bleiben.
      final secondAuth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'alice', email: 'alice@film2watch.app'),
        signedIn: true,
      );
      final secondContainer = await _readyContainer(
        firestore: firestore,
        auth: secondAuth,
        tmdbService: _tmdbService({200: 'Wird geskippt', 201: 'Bleibt übrig'}),
      );
      addTearDown(secondContainer.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: secondContainer,
          child: MaterialApp(home: GroupSwipeScreen(groupId: groupId)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Wird geskippt'), findsNothing);
      expect(find.text('Bleibt übrig'), findsOneWidget);
    });

    testWidgets('Empty State erscheint, wenn nach dem Skip keine weiteren Filme mehr vorhanden sind',
        (tester) async {
      final container = await _readyContainer(
        firestore: firestore,
        auth: auth,
        tmdbService: _tmdbService({300: 'Einziger Film'}),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: GroupSwipeScreen(groupId: groupId)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.watch_later_outlined));
      await tester.pumpAndSettle();

      expect(find.text('Keine weiteren Filme verfügbar.'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('Skip erzeugt keinen Match, auch wenn ein anderes Mitglied denselben Film mag',
        (tester) async {
      await GroupRepository(firestore).acceptInvitation(groupId: groupId, inviteeUid: 'bob');
      await firestore
          .collection('groups')
          .doc(groupId)
          .collection('swipes')
          .doc('bob_400')
          .set({
        'uid': 'bob',
        'movie_id': 400,
        'decision': 'like',
        'created_at': Timestamp.now(),
        'updated_at': Timestamp.now(),
      });

      final container = await _readyContainer(
        firestore: firestore,
        auth: auth,
        tmdbService: _tmdbService({400: 'Gemeinsamer Kandidat'}),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: GroupSwipeScreen(groupId: groupId)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.watch_later_outlined));
      await tester.pumpAndSettle();

      final matches = await firestore.collection('groups').doc(groupId).collection('matches').get();
      expect(matches.docs, isEmpty);
      expect(find.textContaining('Match!'), findsNothing);
    });
  });
}
