import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:film2watch/providers/auth_provider.dart';
import 'package:film2watch/providers/tmdb_provider.dart';
import 'package:film2watch/repositories/group_repository.dart';
import 'package:film2watch/screens/matches/matches_screen.dart';
import 'package:film2watch/screens/movies/movie_detail_screen.dart';
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
      'genres': <dynamic>[],
      'overview': '',
    };

/// Beantwortet Film-Details für ein festes Set an [movies] (id -> Titel);
/// jede andere movie_id liefert einen echten HTTP-Fehler (404) statt eines
/// Fake-Films - simuliert "TMDB für diesen Film nicht erreichbar".
TmdbService _tmdbService(Map<int, String> movies) {
  final client = MockClient((request) async {
    if (request.url.path.contains('/genre/movie/list')) {
      return http.Response(jsonEncode({'genres': <dynamic>[]}), 200);
    }
    final match = RegExp(r'/movie/(\d+)$').firstMatch(request.url.path);
    if (match != null) {
      final id = int.parse(match.group(1)!);
      final title = movies[id];
      if (title != null) return http.Response(jsonEncode(_movieJson(id, title)), 200);
      return http.Response('{"status_message":"not found"}', 404);
    }
    return http.Response('{}', 404);
  });
  return TmdbService(client, accessToken: 'test-token');
}

Future<void> _seedMatch(
  FakeFirebaseFirestore firestore,
  String groupId,
  int movieId,
  DateTime matchedAt,
) {
  return firestore.collection('groups').doc(groupId).collection('matches').doc('$movieId').set({
    'movie_id': movieId,
    'member_uids': ['alice'],
    'matched_at': Timestamp.fromDate(matchedAt),
  });
}

void main() {
  group('MatchesScreen (gruppenübergreifend)', () {
    late FakeFirebaseFirestore firestore;
    late MockFirebaseAuth auth;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      auth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'alice', email: 'alice@film2watch.app'),
        signedIn: true,
      );
    });

    Widget wrap(TmdbService tmdbService) {
      return ProviderScope(
        overrides: [
          firebaseAuthProvider.overrideWithValue(auth),
          firestoreProvider.overrideWithValue(firestore),
          tmdbServiceProvider.overrideWithValue(tmdbService),
        ],
        child: const MaterialApp(home: MatchesScreen()),
      );
    }

    testWidgets('zeigt einen ehrlichen Empty State ohne Matches', (tester) async {
      await tester.pumpWidget(wrap(_tmdbService(const {})));
      await tester.pumpAndSettle();

      expect(find.text('Noch keine gemeinsamen Filme.'), findsOneWidget);
    });

    testWidgets('zeigt Matches aus mehreren Gruppen mit Gruppennamen', (tester) async {
      final groupRepository = GroupRepository(firestore);
      final groupA = await groupRepository.createGroup(name: 'Filmclub', creatorUid: 'alice');
      final groupB = await groupRepository.createGroup(name: 'WG-Abend', creatorUid: 'alice');
      await _seedMatch(firestore, groupA.id, 100, DateTime(2026, 1, 1));
      await _seedMatch(firestore, groupB.id, 200, DateTime(2026, 1, 5));

      await tester.pumpWidget(
        wrap(_tmdbService({100: 'Alter Film', 200: 'Neuer Film'})),
      );
      await tester.pumpAndSettle();

      expect(find.text('Alter Film'), findsOneWidget);
      expect(find.text('Neuer Film'), findsOneWidget);
      expect(find.text('Filmclub'), findsOneWidget);
      expect(find.text('WG-Abend'), findsOneWidget);
    });

    testWidgets('reagiert in Echtzeit auf ein neu entstandenes Match', (tester) async {
      final groupRepository = GroupRepository(firestore);
      final group = await groupRepository.createGroup(name: 'Filmclub', creatorUid: 'alice');

      await tester.pumpWidget(wrap(_tmdbService({300: 'Frischer Match'})));
      await tester.pumpAndSettle();
      expect(find.text('Frischer Match'), findsNothing);

      await _seedMatch(firestore, group.id, 300, DateTime.now());
      await tester.pumpAndSettle();

      expect(find.text('Frischer Match'), findsOneWidget);
    });

    testWidgets('TMDB-Fehler für einen Match blockiert nicht die restliche Liste', (tester) async {
      final groupRepository = GroupRepository(firestore);
      final group = await groupRepository.createGroup(name: 'Filmclub', creatorUid: 'alice');
      await _seedMatch(firestore, group.id, 400, DateTime(2026, 1, 1));
      await _seedMatch(firestore, group.id, 401, DateTime(2026, 1, 2));

      // 400 bleibt ohne TMDB-Antwort (Fehler), nur 401 ist bekannt.
      await tester.pumpWidget(wrap(_tmdbService({401: 'Lädt erfolgreich'})));
      await tester.pumpAndSettle();

      expect(find.text('Lädt erfolgreich'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('Antippen eines Matches öffnet die echten Filmdetails', (tester) async {
      final groupRepository = GroupRepository(firestore);
      final group = await groupRepository.createGroup(name: 'Filmclub', creatorUid: 'alice');
      await _seedMatch(firestore, group.id, 550, DateTime(2026, 1, 1));

      await tester.pumpWidget(wrap(_tmdbService({550: 'Fight Club'})));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Fight Club'));
      await tester.pumpAndSettle();

      final detailScreen = tester.widget<MovieDetailScreen>(find.byType(MovieDetailScreen));
      expect(detailScreen.tmdbId, 550);
    });
  });
}
