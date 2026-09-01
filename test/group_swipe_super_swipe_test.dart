import 'dart:convert';

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

// Super Swipe (§6/§15, Premium-Feature) - die Speicher-/Gating-Logik selbst
// ist bereits vollständig in swipe_service_test.dart und
// swipe_action_controller_test.dart abgedeckt; dieser Test deckt
// ausschließlich den zuvor fehlenden UI-Auslöser ab (Button in
// GroupSwipeScreen -> SwipeCard.triggerSuperSwipe()), analog zu
// group_swipe_watchlist_test.dart/group_swipe_skip_test.dart.

Map<String, dynamic> _movieJson(int id, String title) => {
      'id': id,
      'title': title,
      'genre_ids': <int>[],
    };

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
  group('GroupSwipeScreen - Super Swipe', () {
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

    testWidgets('Premium-Mitglied: Super-Swipe-Button speichert decision == super und zeigt die nächste Karte',
        (tester) async {
      await firestore.collection('premium_status').doc('alice').set({'is_premium': true});
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

      final filmAShownFirst = find.text('Film A').evaluate().isNotEmpty;
      final shownId = filmAShownFirst ? 100 : 101;
      final otherTitle = filmAShownFirst ? 'Film B' : 'Film A';

      await tester.tap(find.byIcon(Icons.star_rounded));
      await tester.pumpAndSettle();

      final swipeDoc = await firestore
          .collection('groups')
          .doc(groupId)
          .collection('swipes')
          .doc('alice_$shownId')
          .get();
      expect(swipeDoc.data()!['decision'], 'super');

      expect(find.text(otherTitle), findsOneWidget);
    });

    testWidgets('Free-Mitglied: Super-Swipe-Button zeigt eine ehrliche Premium-Fehlermeldung statt zu speichern',
        (tester) async {
      // Bewusst KEIN premium_status-Dokument - Normalfall für einen
      // Free-User (siehe PremiumRepository.isPremium).
      final container = await _readyContainer(
        firestore: firestore,
        auth: auth,
        tmdbService: _tmdbService({200: 'Film 200', 201: 'Film 201'}),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: GroupSwipeScreen(groupId: groupId)),
        ),
      );
      await tester.pumpAndSettle();

      final shownTitle = find.text('Film 200').evaluate().isNotEmpty ? 'Film 200' : 'Film 201';

      await tester.tap(find.byIcon(Icons.star_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Super Swipe ist ein Premium-Feature.'), findsOneWidget);
      // Die Karte bleibt unverändert - kein Swipe wurde gespeichert.
      expect(find.text(shownTitle), findsOneWidget);

      final swipes = await firestore.collection('groups').doc(groupId).collection('swipes').get();
      expect(swipes.docs, isEmpty);
    });

    testWidgets('Free-Mitglied sieht ein Schloss-Badge auf dem Super-Swipe-Button', (tester) async {
      await firestore.collection('premium_status').doc('alice').set({'is_premium': false});
      final container = await _readyContainer(
        firestore: firestore,
        auth: auth,
        tmdbService: _tmdbService({300: 'Film 300'}),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: GroupSwipeScreen(groupId: groupId)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.lock), findsOneWidget);
    });

    testWidgets('Premium-Mitglied sieht kein Schloss-Badge auf dem Super-Swipe-Button', (tester) async {
      await firestore.collection('premium_status').doc('alice').set({'is_premium': true});
      final container = await _readyContainer(
        firestore: firestore,
        auth: auth,
        tmdbService: _tmdbService({400: 'Film 400'}),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: GroupSwipeScreen(groupId: groupId)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.lock), findsNothing);
    });
  });
}
