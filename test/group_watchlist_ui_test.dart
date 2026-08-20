import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:film2watch/providers/auth_provider.dart';
import 'package:film2watch/providers/tmdb_provider.dart';
import 'package:film2watch/repositories/group_repository.dart';
import 'package:film2watch/screens/groups/group_detail_screen.dart';
import 'package:film2watch/screens/movies/movie_detail_screen.dart';
import 'package:film2watch/services/tmdb_service.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

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

    Widget wrap(TmdbService tmdbService) {
      return ProviderScope(
        overrides: [
          firebaseAuthProvider.overrideWithValue(auth),
          firestoreProvider.overrideWithValue(firestore),
          tmdbServiceProvider.overrideWithValue(tmdbService),
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
  });
}
