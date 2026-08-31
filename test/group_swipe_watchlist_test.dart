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
/// aufgelöst ist, bevor der Screen gepumpt wird. Siehe
/// `group_swipe_skip_test.dart` für die ausführliche Begründung - dieselbe
/// Vorwärmung ist hier nötig, damit `SwipeQueueController.build()` beim
/// allerersten Aufbau nicht mit "benötigt einen eingeloggten User" abbricht.
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
  group('GroupSwipeScreen - Watchlist', () {
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

    testWidgets('Watchlist-Button speichert decision == watchlist und zeigt danach die nächste Karte',
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

      // Ohne Freundes-Boost-Signal entscheidet §7/§18s "ORDER BY friend_likes
      // DESC, RANDOM()" zufällig, welcher der beiden Filme zuerst gezeigt
      // wird - der Test darf sich daher nicht auf eine feste Reihenfolge
      // verlassen, nur auf die tatsächlich angezeigte erste Karte.
      final filmAShownFirst = find.text('Film A').evaluate().isNotEmpty;
      final shownId = filmAShownFirst ? 100 : 101;
      final otherTitle = filmAShownFirst ? 'Film B' : 'Film A';

      await tester.tap(find.byIcon(Icons.bookmark_add_outlined));
      await tester.pumpAndSettle();

      final swipeDoc = await firestore
          .collection('groups')
          .doc(groupId)
          .collection('swipes')
          .doc('alice_$shownId')
          .get();
      expect(swipeDoc.data()!['decision'], 'watchlist');

      // Die nächste (bislang nicht gezeigte) Karte ist jetzt sichtbar.
      expect(find.text(otherTitle), findsOneWidget);
      expect(find.text(filmAShownFirst ? 'Film A' : 'Film B'), findsNothing);
    });

    testWidgets('Film auf der Watchlist erscheint nicht erneut, wenn der Screen neu aufgebaut wird',
        (tester) async {
      final firstContainer = await _readyContainer(
        firestore: firestore,
        auth: auth,
        tmdbService: _tmdbService({200: 'Film 200', 201: 'Film 201'}),
      );
      addTearDown(firstContainer.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: firstContainer,
          child: MaterialApp(home: GroupSwipeScreen(groupId: groupId)),
        ),
      );
      await tester.pumpAndSettle();

      // Ohne Freundes-Boost-Signal entscheidet §7/§18s "ORDER BY friend_likes
      // DESC, RANDOM()" zufällig, welcher der beiden Filme zuerst gezeigt
      // wird - der Test merkt sich bewusst den tatsächlich zuerst gezeigten.
      final film200ShownFirst = find.text('Film 200').evaluate().isNotEmpty;
      final watchlistedTitle = film200ShownFirst ? 'Film 200' : 'Film 201';
      final remainingTitle = film200ShownFirst ? 'Film 201' : 'Film 200';

      await tester.tap(find.byIcon(Icons.bookmark_add_outlined));
      await tester.pumpAndSettle();
      expect(find.text(remainingTitle), findsOneWidget);

      // Ein komplett neuer Screen-/Provider-Aufbau (simuliert Pagination
      // bzw. einen App-Neustart), der die bereits in Firestore gespeicherte
      // Watchlist-Entscheidung erneut einliest - der Film darf trotzdem
      // nicht wieder auftauchen. Eigene MockFirebaseAuth-Instanz (derselbe
      // User), weil `authStateChanges()` von firebase_auth_mocks ihr
      // einziges Event nur einmal pro Instanz liefert.
      final secondAuth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'alice', email: 'alice@film2watch.app'),
        signedIn: true,
      );
      final secondContainer = await _readyContainer(
        firestore: firestore,
        auth: secondAuth,
        tmdbService: _tmdbService({200: 'Film 200', 201: 'Film 201'}),
      );
      addTearDown(secondContainer.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: secondContainer,
          child: MaterialApp(home: GroupSwipeScreen(groupId: groupId)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(watchlistedTitle), findsNothing);
      expect(find.text(remainingTitle), findsOneWidget);
    });

    testWidgets('Empty State erscheint, wenn nach der Watchlist-Aktion keine weiteren Filme mehr vorhanden sind',
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

      await tester.tap(find.byIcon(Icons.bookmark_add_outlined));
      await tester.pumpAndSettle();

      expect(find.text('Keine weiteren Filme verfügbar.'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('Watchlist erzeugt keinen Match, auch wenn ein anderes Mitglied denselben Film mag (Watchlist + Like)',
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

      await tester.tap(find.byIcon(Icons.bookmark_add_outlined));
      await tester.pumpAndSettle();

      final matches = await firestore.collection('groups').doc(groupId).collection('matches').get();
      expect(matches.docs, isEmpty);
      expect(find.textContaining('Match!'), findsNothing);
    });

    testWidgets('mehrfaches schnelles Antippen des Watchlist-Buttons verhindert Double-Submit', (tester) async {
      final container = await _readyContainer(
        firestore: firestore,
        auth: auth,
        tmdbService: _tmdbService({500: 'Film X', 501: 'Film Y'}),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: GroupSwipeScreen(groupId: groupId)),
        ),
      );
      await tester.pumpAndSettle();

      // Ohne Freundes-Boost-Signal entscheidet §7/§18s "ORDER BY friend_likes
      // DESC, RANDOM()" zufällig, welcher der beiden Filme zuerst gezeigt
      // wird - der Test prüft daher den tatsächlich zuerst gezeigten.
      final shownId = find.text('Film X').evaluate().isNotEmpty ? 500 : 501;

      // Zwei Taps ohne dazwischenliegendes Settle - der zweite Tap trifft
      // während des laufenden Speichervorgangs auf einen deaktivierten
      // Button (`enabled: !isBusy`).
      await tester.tap(find.byIcon(Icons.bookmark_add_outlined));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.bookmark_add_outlined), warnIfMissed: false);
      await tester.pumpAndSettle();

      final snapshot = await firestore
          .collection('groups')
          .doc(groupId)
          .collection('swipes')
          .where('movie_id', isEqualTo: shownId)
          .get();
      expect(snapshot.docs, hasLength(1));
    });
  });
}
