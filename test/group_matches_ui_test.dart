import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:film2watch/providers/auth_provider.dart';
import 'package:film2watch/providers/tmdb_provider.dart';
import 'package:film2watch/repositories/group_repository.dart';
import 'package:film2watch/screens/groups/group_detail_screen.dart';
import 'package:film2watch/screens/groups/group_swipe_screen.dart';
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
/// festes Set an [movies] (id -> Titel). Löst nie echte HTTP-Requests aus.
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
    }
    return http.Response('{}', 404);
  });
  return TmdbService(client, accessToken: 'test-token');
}

void main() {
  group('Gruppen-Matches UI', () {
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

    testWidgets('zeigt einen ehrlichen Empty State, wenn die Gruppe noch keine Matches hat',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firebaseAuthProvider.overrideWithValue(auth),
            firestoreProvider.overrideWithValue(firestore),
            tmdbServiceProvider.overrideWithValue(_tmdbService(const {})),
          ],
          child: MaterialApp(home: GroupDetailScreen(groupId: groupId)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Noch kein gemeinsamer Film.'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('zeigt eine Match-Karte mit echten TMDB-Daten, wenn ein Match existiert',
        (tester) async {
      await firestore.collection('groups').doc(groupId).collection('matches').doc('550').set({
        'movie_id': 550,
        'member_uids': ['alice', 'bob'],
        'matched_at': Timestamp.now(),
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firebaseAuthProvider.overrideWithValue(auth),
            firestoreProvider.overrideWithValue(firestore),
            tmdbServiceProvider.overrideWithValue(_tmdbService({550: 'Fight Club'})),
          ],
          child: MaterialApp(home: GroupDetailScreen(groupId: groupId)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Fight Club'), findsOneWidget);
      expect(find.text('Noch kein gemeinsamer Film.'), findsNothing);
    });

    testWidgets('zeigt einen Match!-Dialog, wenn während der Swipe-Session ein neues Match entsteht',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firebaseAuthProvider.overrideWithValue(auth),
            firestoreProvider.overrideWithValue(firestore),
            tmdbServiceProvider.overrideWithValue(_tmdbService({777: 'Gemeinsamer Film'})),
          ],
          child: MaterialApp(home: GroupSwipeScreen(groupId: groupId)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Match!'), findsNothing);

      // Simuliert das Ergebnis der Cloud Function (siehe functions/index.js) -
      // die eigentliche Erkennungslogik wird separat in
      // functions/test/matchEngine.test.mjs gegen den echten Functions-
      // Emulator getestet; hier wird nur die reaktive UI verifiziert.
      await firestore.collection('groups').doc(groupId).collection('matches').doc('777').set({
        'movie_id': 777,
        'member_uids': ['alice'],
        'matched_at': Timestamp.now(),
      });
      await tester.pumpAndSettle();

      expect(find.textContaining('Match!'), findsOneWidget);
      expect(find.text('Gemeinsamer Film'), findsOneWidget);
    });
  });
}
