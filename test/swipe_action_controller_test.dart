import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:film2watch/models/movie_swipe.dart';
import 'package:film2watch/providers/auth_provider.dart';
import 'package:film2watch/providers/group_provider.dart';
import 'package:film2watch/providers/swipe_action_controller.dart';
import 'package:film2watch/providers/swipe_provider.dart';
import 'package:film2watch/providers/tmdb_provider.dart';
import 'package:film2watch/services/tmdb_service.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Antwortet auf jede Discover/Genre-Anfrage mit einer leeren Seite - die
/// Aktions-Tests interessieren sich nicht für die Warteschlange selbst,
/// lösen aber über `advancePastCurrent` intern einen Aufbau der
/// Warteschlange aus. Kein echter Netzwerk-Request.
TmdbService _emptyTmdbService() {
  final client = MockClient((request) async {
    if (request.url.path.contains('/genre/movie/list')) {
      return http.Response(jsonEncode({'genres': <dynamic>[]}), 200);
    }
    return http.Response(
      jsonEncode({'page': 1, 'total_pages': 1, 'total_results': 0, 'results': <dynamic>[]}),
      200,
    );
  });
  return TmdbService(client, accessToken: 'test-token');
}

void main() {
  group('SwipeActionController', () {
    late FakeFirebaseFirestore firestore;
    late ProviderContainer container;
    late String groupId;

    setUp(() async {
      firestore = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'alice', email: 'alice@film2watch.app'),
        signedIn: true,
      );
      container = ProviderContainer(
        overrides: [
          firebaseAuthProvider.overrideWithValue(auth),
          firestoreProvider.overrideWithValue(firestore),
          tmdbServiceProvider.overrideWithValue(_emptyTmdbService()),
        ],
      );
      addTearDown(container.dispose);
      // MockFirebaseAuth feuert sein initiales Sign-in-Event auf einem
      // Broadcast-Stream ohne Replay - der Listener muss deshalb im selben
      // synchronen Abschnitt registriert werden, noch vor jedem `await`.
      container.listen(authStateChangesProvider, (previous, next) {});
      await container.read(authStateChangesProvider.future);

      final group = await container.read(groupRepositoryProvider).createGroup(
            name: 'Filmabend',
            creatorUid: 'alice',
          );
      groupId = group.id;

      // Den (trivialen) Erstaufbau des Controllers abwarten, bevor Aktionen
      // ausgelöst werden - sonst würde der `state.isLoading`-Schutz gegen
      // Doppel-Submits fälschlich den noch laufenden Erstaufbau als "bereits
      // aktiv" werten und den allerersten Aufruf stillschweigend verwerfen.
      await container.read(swipeActionControllerProvider(groupId).future);
    });

    test('Status durchläuft Loading, bevor er im Erfolg landet', () async {
      final states = <bool>[];
      container.listen(
        swipeActionControllerProvider(groupId),
        (previous, next) => states.add(next.isLoading),
        fireImmediately: true,
      );

      await container.read(swipeActionControllerProvider(groupId).notifier).like(1);

      expect(states, contains(true));
      expect(states.last, isFalse);
    });

    test('Status landet im Erfolg nach erfolgreichem Speichern', () async {
      final notifier = container.read(swipeActionControllerProvider(groupId).notifier);

      await notifier.like(1);

      expect(container.read(swipeActionControllerProvider(groupId)).hasError, isFalse);
      final swipe = await container
          .read(swipeRepositoryProvider)
          .getSwipe(groupId: groupId, uid: 'alice', movieId: 1);
      expect(swipe, isNotNull);
    });

    test('Status landet im Error, wenn das Speichern fehlschlägt (Nicht-Mitglied)', () async {
      final foreignAuth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'carol', email: 'carol@film2watch.app'),
        signedIn: true,
      );
      final foreignContainer = ProviderContainer(
        overrides: [
          firebaseAuthProvider.overrideWithValue(foreignAuth),
          firestoreProvider.overrideWithValue(firestore),
          tmdbServiceProvider.overrideWithValue(_emptyTmdbService()),
        ],
      );
      addTearDown(foreignContainer.dispose);
      foreignContainer.listen(authStateChangesProvider, (previous, next) {});
      await foreignContainer.read(authStateChangesProvider.future);
      await foreignContainer.read(swipeActionControllerProvider(groupId).future);

      final notifier = foreignContainer.read(swipeActionControllerProvider(groupId).notifier);
      await notifier.like(2);

      expect(foreignContainer.read(swipeActionControllerProvider(groupId)).hasError, isTrue);
    });

    test('mehrfaches schnelles Antippen erzeugt nur einen einzigen Swipe', () async {
      final notifier = container.read(swipeActionControllerProvider(groupId).notifier);

      final first = notifier.like(3);
      final second = notifier.like(3);
      await Future.wait([first, second]);

      final snapshot = await firestore
          .collection('groups')
          .doc(groupId)
          .collection('swipes')
          .where('movie_id', isEqualTo: 3)
          .get();
      expect(snapshot.docs, hasLength(1));
    });

    test('Skip landet im Erfolg und speichert decision == skip', () async {
      final notifier = container.read(swipeActionControllerProvider(groupId).notifier);

      await notifier.skip(4);

      expect(container.read(swipeActionControllerProvider(groupId)).hasError, isFalse);
      final swipe = await container
          .read(swipeRepositoryProvider)
          .getSwipe(groupId: groupId, uid: 'alice', movieId: 4);
      expect(swipe, isNotNull);
      expect(swipe!.decision, SwipeDecision.skip);
    });

    test('mehrfaches schnelles Skippen (schnelle Mehrfachaktion) erzeugt nur einen einzigen Swipe', () async {
      final notifier = container.read(swipeActionControllerProvider(groupId).notifier);

      final first = notifier.skip(5);
      final second = notifier.skip(5);
      await Future.wait([first, second]);

      final snapshot = await firestore
          .collection('groups')
          .doc(groupId)
          .collection('swipes')
          .where('movie_id', isEqualTo: 5)
          .get();
      expect(snapshot.docs, hasLength(1));
      expect(snapshot.docs.first.data()['decision'], 'skip');
    });

    test('Watchlist landet im Erfolg und speichert decision == watchlist', () async {
      final notifier = container.read(swipeActionControllerProvider(groupId).notifier);

      await notifier.watchlist(6);

      expect(container.read(swipeActionControllerProvider(groupId)).hasError, isFalse);
      final swipe = await container
          .read(swipeRepositoryProvider)
          .getSwipe(groupId: groupId, uid: 'alice', movieId: 6);
      expect(swipe, isNotNull);
      expect(swipe!.decision, SwipeDecision.watchlist);
    });

    test('mehrfaches schnelles Antippen des Watchlist-Buttons (Double-Submit) erzeugt nur einen einzigen Swipe',
        () async {
      final notifier = container.read(swipeActionControllerProvider(groupId).notifier);

      final first = notifier.watchlist(7);
      final second = notifier.watchlist(7);
      await Future.wait([first, second]);

      final snapshot = await firestore
          .collection('groups')
          .doc(groupId)
          .collection('swipes')
          .where('movie_id', isEqualTo: 7)
          .get();
      expect(snapshot.docs, hasLength(1));
      expect(snapshot.docs.first.data()['decision'], 'watchlist');
    });

    // Super Swipe (§6/§15, Premium-Feature) - die reine Speicher-/
    // Gating-Logik ist bereits vollständig in swipe_service_test.dart
    // abgedeckt; hier nur die Controller-Ebene (Loading-/Error-Zustand,
    // Double-Submit), analog zu den bestehenden like/skip/watchlist-Tests
    // oben.
    test('Super Swipe landet im Erfolg und speichert decision == super, wenn der User Premium hat', () async {
      await firestore.collection('premium_status').doc('alice').set({'is_premium': true});
      final notifier = container.read(swipeActionControllerProvider(groupId).notifier);

      await notifier.superSwipe(8);

      expect(container.read(swipeActionControllerProvider(groupId)).hasError, isFalse);
      final swipe = await container
          .read(swipeRepositoryProvider)
          .getSwipe(groupId: groupId, uid: 'alice', movieId: 8);
      expect(swipe, isNotNull);
      expect(swipe!.decision, SwipeDecision.superSwipe);
    });

    test('Super Swipe landet im Error, wenn der User kein Premium hat (Free-User)', () async {
      final notifier = container.read(swipeActionControllerProvider(groupId).notifier);

      await notifier.superSwipe(9);

      expect(container.read(swipeActionControllerProvider(groupId)).hasError, isTrue);
      final swipe = await container
          .read(swipeRepositoryProvider)
          .getSwipe(groupId: groupId, uid: 'alice', movieId: 9);
      expect(swipe, isNull);
    });

    test('mehrfaches schnelles Super-Swipen (Double-Submit) erzeugt nur einen einzigen Swipe', () async {
      await firestore.collection('premium_status').doc('alice').set({'is_premium': true});
      final notifier = container.read(swipeActionControllerProvider(groupId).notifier);

      final first = notifier.superSwipe(10);
      final second = notifier.superSwipe(10);
      await Future.wait([first, second]);

      final snapshot = await firestore
          .collection('groups')
          .doc(groupId)
          .collection('swipes')
          .where('movie_id', isEqualTo: 10)
          .get();
      expect(snapshot.docs, hasLength(1));
      expect(snapshot.docs.first.data()['decision'], 'super');
    });
  });
}
