import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:film2watch/providers/auth_provider.dart';
import 'package:film2watch/providers/swipe_provider.dart';
import 'package:film2watch/providers/tmdb_provider.dart';
import 'package:film2watch/repositories/group_repository.dart';
import 'package:film2watch/repositories/premium_repository.dart';
import 'package:film2watch/repositories/swipe_repository.dart';
import 'package:film2watch/screens/groups/group_detail_screen.dart';
import 'package:film2watch/screens/movies/movie_detail_screen.dart';
import 'package:film2watch/services/swipe_service.dart';
import 'package:film2watch/services/tmdb_service.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Verzögertes [SwipeService], um den Loading-/Disabled-Zustand während
/// eines laufenden Löschvorgangs deterministisch beobachten zu können
/// (analog zum `_DelayedChatService`-Muster in `chat_ui_test.dart`).
class _DelayedSwipeService extends SwipeService {
  _DelayedSwipeService(super.swipeRepository, super.groupRepository, super.premiumRepository);

  @override
  Future<void> removeFromWatchlist({
    required String groupId,
    required String uid,
    required int movieId,
  }) async {
    await Future.delayed(const Duration(milliseconds: 100));
    await super.removeFromWatchlist(groupId: groupId, uid: uid, movieId: movieId);
  }
}

Map<String, dynamic> _movieDetailsJson(int id, {String title = 'Testfilm'}) => {
      'id': id,
      'title': title,
      'genres': <dynamic>[],
      'overview': '',
    };

/// Beantwortet Discover (immer leer), Genre-Liste und Film-Details für ein
/// festes Set an [movies] (id -> Titel). Jede unbekannte movie_id liefert
/// einen echten HTTP-404 statt eines Fake-Films - simuliert "TMDB für
/// diesen Film nicht erreichbar" bzw. ungültige/fehlende Filmdaten. Löst nie
/// echte HTTP-Requests aus.
TmdbService _tmdbService(Map<int, String> movies) {
  final client = MockClient((request) async {
    if (request.url.path.contains('/genre/movie/list')) {
      return http.Response(jsonEncode({'genres': <dynamic>[]}), 200);
    }
    if (request.url.path.contains('/discover/movie')) {
      return http.Response(
        jsonEncode({'page': 1, 'total_pages': 1, 'total_results': 0, 'results': <dynamic>[]}),
        200,
      );
    }
    final match = RegExp(r'/movie/(\d+)$').firstMatch(request.url.path);
    if (match != null) {
      final id = int.parse(match.group(1)!);
      final title = movies[id];
      if (title != null) {
        return http.Response(jsonEncode(_movieDetailsJson(id, title: title)), 200);
      }
      return http.Response('{"status_message":"not found"}', 404);
    }
    return http.Response('{}', 404);
  });
  return TmdbService(client, accessToken: 'test-token');
}

Future<void> _seedWatchlist(
  FakeFirebaseFirestore firestore,
  String groupId,
  String uid,
  int movieId,
) {
  return firestore.collection('groups').doc(groupId).collection('swipes').doc('${uid}_$movieId').set({
    'uid': uid,
    'movie_id': movieId,
    'decision': 'watchlist',
    'created_at': Timestamp.now(),
    'updated_at': Timestamp.now(),
  });
}

void main() {
  group('Gruppen-Watchlist UI', () {
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

    Widget wrap(TmdbService tmdbService, {SwipeService? swipeService}) {
      return ProviderScope(
        overrides: [
          firebaseAuthProvider.overrideWithValue(auth),
          firestoreProvider.overrideWithValue(firestore),
          tmdbServiceProvider.overrideWithValue(tmdbService),
          if (swipeService != null) swipeServiceProvider.overrideWithValue(swipeService),
        ],
        child: MaterialApp(home: GroupDetailScreen(groupId: groupId)),
      );
    }

    testWidgets('zeigt einen ehrlichen Empty State, wenn niemand etwas vorgemerkt hat', (tester) async {
      await tester.pumpWidget(wrap(_tmdbService(const {})));
      await tester.pumpAndSettle();

      expect(find.text('Noch keine Filme auf der Watchlist.'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('zeigt eine Watchlist-Karte mit echten TMDB-Daten und "Du hast vorgemerkt"',
        (tester) async {
      await _seedWatchlist(firestore, groupId, 'alice', 550);

      await tester.pumpWidget(wrap(_tmdbService({550: 'Fight Club'})));
      await tester.pumpAndSettle();

      expect(find.text('Fight Club'), findsOneWidget);
      expect(find.text('Du hast vorgemerkt'), findsOneWidget);
      expect(find.text('Noch keine Filme auf der Watchlist.'), findsNothing);
    });

    testWidgets('zeigt den Gruppen-Abgleich "X/Y vorgemerkt", wenn mehrere Mitglieder denselben Film vorgemerkt haben',
        (tester) async {
      await GroupRepository(firestore).acceptInvitation(groupId: groupId, inviteeUid: 'bob');
      await _seedWatchlist(firestore, groupId, 'alice', 551);
      await _seedWatchlist(firestore, groupId, 'bob', 551);

      await tester.pumpWidget(wrap(_tmdbService({551: 'Inception'})));
      await tester.pumpAndSettle();

      expect(find.text('Inception'), findsOneWidget);
      expect(find.text('2/2 vorgemerkt'), findsOneWidget);
    });

    testWidgets('TMDB-Fehler für einen Watchlist-Film blockiert nicht die restliche Liste', (tester) async {
      await _seedWatchlist(firestore, groupId, 'alice', 552);
      await _seedWatchlist(firestore, groupId, 'alice', 553);

      // 552 bleibt ohne TMDB-Antwort (Fehler), nur 553 ist bekannt.
      await tester.pumpWidget(wrap(_tmdbService({553: 'Bekannter Film'})));
      await tester.pumpAndSettle();

      expect(find.text('Bekannter Film'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('Antippen einer Watchlist-Karte öffnet die echten Filmdetails', (tester) async {
      await _seedWatchlist(firestore, groupId, 'alice', 554);

      // Die Watchlist-Sektion liegt unterhalb der Matches-Sektion in der
      // scrollbaren GroupDetailScreen-Liste - ein größerer Viewport macht
      // sie ohne fragiles Scrollen direkt antippbar.
      addTearDown(tester.view.resetPhysicalSize);
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(wrap(_tmdbService({554: 'Pulp Fiction'})));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Pulp Fiction'));
      await tester.pumpAndSettle();

      final detailScreen = tester.widget<MovieDetailScreen>(find.byType(MovieDetailScreen));
      expect(detailScreen.tmdbId, 554);
    });

    testWidgets('Like/Dislike/Skip-Swipes erscheinen nicht in der Watchlist-Sektion', (tester) async {
      await firestore.collection('groups').doc(groupId).collection('swipes').doc('alice_600').set({
        'uid': 'alice',
        'movie_id': 600,
        'decision': 'like',
        'created_at': Timestamp.now(),
        'updated_at': Timestamp.now(),
      });

      await tester.pumpWidget(wrap(_tmdbService({600: 'Nur geliked'})));
      await tester.pumpAndSettle();

      expect(find.text('Nur geliked'), findsNothing);
      expect(find.text('Noch keine Filme auf der Watchlist.'), findsOneWidget);
    });

    testWidgets('zeigt einen Entfernen-Button auf dem eigenen Watchlist-Eintrag', (tester) async {
      await _seedWatchlist(firestore, groupId, 'alice', 800);

      await tester.pumpWidget(wrap(_tmdbService({800: 'Eigener Film'})));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('zeigt keinen Entfernen-Button auf dem Watchlist-Eintrag eines anderen Mitglieds',
        (tester) async {
      await GroupRepository(firestore).acceptInvitation(groupId: groupId, inviteeUid: 'bob');
      await _seedWatchlist(firestore, groupId, 'bob', 801);

      await tester.pumpWidget(wrap(_tmdbService({801: 'Bobs Film'})));
      await tester.pumpAndSettle();

      expect(find.text('Bobs Film'), findsOneWidget);
      expect(find.byIcon(Icons.close), findsNothing);
    });

    testWidgets('Entfernen-Button löscht den eigenen Watchlist-Eintrag und aktualisiert die Liste sofort',
        (tester) async {
      await _seedWatchlist(firestore, groupId, 'alice', 802);

      addTearDown(tester.view.resetPhysicalSize);
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(wrap(_tmdbService({802: 'Wird entfernt'})));
      await tester.pumpAndSettle();

      expect(find.text('Wird entfernt'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.text('Wird entfernt'), findsNothing);
      expect(find.text('Noch keine Filme auf der Watchlist.'), findsOneWidget);

      final swipeDoc = await firestore
          .collection('groups')
          .doc(groupId)
          .collection('swipes')
          .doc('alice_802')
          .get();
      expect(swipeDoc.exists, isFalse);
    });

    testWidgets('Entfernen aktualisiert den Gruppen-Abgleich korrekt, wenn ein anderes Mitglied den Film weiterhin vorgemerkt hat',
        (tester) async {
      await GroupRepository(firestore).acceptInvitation(groupId: groupId, inviteeUid: 'bob');
      await _seedWatchlist(firestore, groupId, 'alice', 803);
      await _seedWatchlist(firestore, groupId, 'bob', 803);

      addTearDown(tester.view.resetPhysicalSize);
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(wrap(_tmdbService({803: 'Geteilter Film'})));
      await tester.pumpAndSettle();

      expect(find.text('2/2 vorgemerkt'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      // Bobs Eintrag bleibt bestehen, der Film ist weiterhin auf der Liste,
      // aber jetzt mit dem für alice korrekt aktualisierten Abgleich.
      expect(find.text('Geteilter Film'), findsOneWidget);
      expect(find.text('2/2 vorgemerkt'), findsNothing);

      final bobSwipe = await firestore
          .collection('groups')
          .doc(groupId)
          .collection('swipes')
          .doc('bob_803')
          .get();
      expect(bobSwipe.data()!['decision'], 'watchlist');
    });

    testWidgets('mehrfaches schnelles Antippen des Entfernen-Buttons verhindert Double-Submit', (tester) async {
      await _seedWatchlist(firestore, groupId, 'alice', 804);

      addTearDown(tester.view.resetPhysicalSize);
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;

      // Künstlich verzögerter SwipeService, damit der Ladezustand
      // zwischen den beiden Taps tatsächlich beobachtbar ist -
      // `FakeFirebaseFirestore` löst ein Löschen sonst so schnell auf, dass
      // die Karte nach dem ersten `pump()` bereits komplett verschwunden ist.
      final delayedService = _DelayedSwipeService(
        SwipeRepository(firestore),
        GroupRepository(firestore),
        PremiumRepository(firestore),
      );

      await tester.pumpWidget(
        wrap(_tmdbService({804: 'Doppelklick-Film'}), swipeService: delayedService),
      );
      await tester.pumpAndSettle();

      // Zwei Taps auf denselben Button (stabiler Key statt Icon-Finder, da
      // das Icon während des Löschvorgangs durch einen Ladeindikator ersetzt
      // wird) ohne dazwischenliegendes Settle - der zweite Tap trifft
      // während des laufenden Löschvorgangs auf einen bereits deaktivierten
      // Button.
      final removeButton = find.byKey(const Key('watchlist_remove_804'));
      await tester.tap(removeButton);
      await tester.pump();
      await tester.tap(removeButton, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.text('Doppelklick-Film'), findsNothing);

      final snapshot = await firestore
          .collection('groups')
          .doc(groupId)
          .collection('swipes')
          .where('movie_id', isEqualTo: 804)
          .get();
      expect(snapshot.docs, isEmpty);
    });

    testWidgets('Entfernen eines bereits entfernten Eintrags zeigt einen verständlichen Fehler',
        (tester) async {
      await _seedWatchlist(firestore, groupId, 'alice', 805);

      addTearDown(tester.view.resetPhysicalSize);
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(wrap(_tmdbService({805: 'Fehlerfall'})));
      await tester.pumpAndSettle();

      // Entfernt den Eintrag direkt in Firestore, ohne über die UI zu gehen -
      // simuliert eine Race Condition (z. B. Entfernen auf einem zweiten
      // Gerät), bevor der UI-Tap auf den bereits verschwundenen Eintrag trifft.
      await firestore.collection('groups').doc(groupId).collection('swipes').doc('alice_805').delete();

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.textContaining('nicht auf deiner Watchlist'), findsOneWidget);
    });
  });
}
