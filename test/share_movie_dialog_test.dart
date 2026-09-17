import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:film2watch/components/movies/share_movie_dialog.dart';
import 'package:film2watch/providers/auth_provider.dart';
import 'package:film2watch/providers/tmdb_provider.dart';
import 'package:film2watch/repositories/group_repository.dart';
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

TmdbService _tmdbService() {
  final client = MockClient((request) async {
    if (request.url.path.contains('/videos')) {
      return http.Response(jsonEncode({'results': <dynamic>[]}), 200);
    }
    if (request.url.path.contains('/watch/providers')) {
      return http.Response(jsonEncode({'results': <String, dynamic>{}}), 200);
    }
    final match = RegExp(r'/movie/(\d+)$').firstMatch(request.url.path);
    if (match != null) {
      return http.Response(jsonEncode(_movieDetailsJson(int.parse(match.group(1)!))), 200);
    }
    return http.Response('{}', 404);
  });
  return TmdbService(client, accessToken: 'test-token');
}

Future<ProviderContainer> _readyContainer({
  required FakeFirebaseFirestore firestore,
  required MockFirebaseAuth auth,
}) async {
  final container = ProviderContainer(
    overrides: [
      firebaseAuthProvider.overrideWithValue(auth),
      firestoreProvider.overrideWithValue(firestore),
      tmdbServiceProvider.overrideWithValue(_tmdbService()),
    ],
  );
  container.listen(authStateChangesProvider, (previous, next) {});
  await container.read(authStateChangesProvider.future);
  return container;
}

/// `ShareMovieDialog` liest die Gruppenliste über `myGroupsProvider`, das
/// jetzt den serverseitig gepflegten User-Group-Index
/// (`users/{uid}/groups/{id}`, siehe README "Architekturentscheidung") liest -
/// `fake_cloud_firestore` führt den dafür zuständigen Cloud-Function-Trigger
/// nicht aus, daher hier direkt nachgebildet.
Future<void> _seedUserGroupIndex(FakeFirebaseFirestore firestore, String uid, String groupId) {
  return firestore.collection('users').doc(uid).collection('groups').doc(groupId).set({
    'groupId': groupId,
  });
}

void main() {
  group('MovieDetailScreen - Filmkarten teilen (§11)', () {
    late FakeFirebaseFirestore firestore;
    late MockFirebaseAuth auth;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      auth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'alice', email: 'alice@film2watch.app'),
        signedIn: true,
      );
    });

    testWidgets('Teilen-Button öffnet einen Dialog mit den eigenen Gruppen', (tester) async {
      final group = await GroupRepository(firestore).createGroup(name: 'Filmabend', creatorUid: 'alice');
      await _seedUserGroupIndex(firestore, 'alice', group.id);

      final container = await _readyContainer(firestore: firestore, auth: auth);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: MovieDetailScreen(tmdbId: 550)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.ios_share));
      await tester.pumpAndSettle();

      expect(find.byType(ShareMovieDialog), findsOneWidget);
      expect(find.text('Filmabend'), findsOneWidget);
    });

    testWidgets(
        'Antippen einer Gruppe teilt den Film als Chat-Nachricht und schließt den Dialog',
        (tester) async {
      final group =
          await GroupRepository(firestore).createGroup(name: 'Filmabend', creatorUid: 'alice');
      await _seedUserGroupIndex(firestore, 'alice', group.id);

      final container = await _readyContainer(firestore: firestore, auth: auth);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: MovieDetailScreen(tmdbId: 550)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.ios_share));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Filmabend'));
      await tester.pumpAndSettle();

      expect(find.byType(ShareMovieDialog), findsNothing);
      expect(find.text('Film wurde geteilt.'), findsOneWidget);

      final messages = await firestore.collection('groups/${group.id}/messages').get();
      expect(messages.docs, hasLength(1));
      final data = messages.docs.single.data();
      expect(data['type'], 'movie_share');
      expect(data['sender_uid'], 'alice');
      expect(data['movie_id'], 550);
    });

    testWidgets('zeigt einen Hinweis, wenn der Nutzer in keiner Gruppe ist', (tester) async {
      final container = await _readyContainer(firestore: firestore, auth: auth);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: MovieDetailScreen(tmdbId: 550)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.ios_share));
      await tester.pumpAndSettle();

      expect(find.text('Du bist noch in keiner Gruppe.'), findsOneWidget);
    });
  });
}
