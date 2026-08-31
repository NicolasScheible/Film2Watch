import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:film2watch/models/movie_filter.dart';
import 'package:film2watch/providers/auth_provider.dart';
import 'package:film2watch/providers/movie_filter_provider.dart';
import 'package:film2watch/providers/tmdb_provider.dart';
import 'package:film2watch/repositories/group_repository.dart';
import 'package:film2watch/screens/groups/group_swipe_screen.dart';
import 'package:film2watch/screens/movies/movie_filter_screen.dart';
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

/// Discover liefert exakt [movies] auf Seite 1; `/genre/movie/list` liefert
/// [genres] (id -> Name); `/watch/providers/movie` liefert [providers]
/// (id -> Name). Löst nie echte HTTP-Requests aus.
TmdbService _tmdbService({
  Map<int, String> movies = const {},
  Map<int, String> genres = const {},
  Map<int, String> providers = const {},
}) {
  final client = MockClient((request) async {
    if (request.url.path.contains('/genre/movie/list')) {
      return http.Response(
        jsonEncode({
          'genres': genres.entries.map((e) => {'id': e.key, 'name': e.value}).toList(),
        }),
        200,
      );
    }
    if (request.url.path.contains('/watch/providers/movie')) {
      return http.Response(
        jsonEncode({
          'results': providers.entries
              .map((e) => {'provider_id': e.key, 'provider_name': e.value, 'logo_path': null})
              .toList(),
        }),
        200,
      );
    }
    if (request.url.path.contains('/discover/movie')) {
      final page = int.parse(request.url.queryParameters['page'] ?? '1');
      final results =
          page == 1 ? movies.entries.map((e) => _movieJson(e.key, e.value)).toList() : <dynamic>[];
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
  group('MovieFilterScreen', () {
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

    testWidgets('zeigt echte TMDB-Plattformen und Genres zur Auswahl an', (tester) async {
      final container = await _readyContainer(
        firestore: firestore,
        auth: auth,
        tmdbService: _tmdbService(
          providers: {8: 'Netflix', 9: 'Amazon Prime Video'},
          genres: {28: 'Action', 12: 'Abenteuer'},
        ),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: MovieFilterScreen(groupId: groupId)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Netflix'), findsOneWidget);
      expect(find.text('Amazon Prime Video'), findsOneWidget);
      expect(find.text('Action'), findsOneWidget);
      expect(find.text('Abenteuer'), findsOneWidget);
    });

    testWidgets('Plattform auswählen und Anwenden speichert die Auswahl im Filter-Provider',
        (tester) async {
      // "Anwenden" liegt am Ende der scrollbaren Filterliste unterhalb des
      // Standard-Testviewports (800x600) - ein größerer Viewport macht es
      // ohne fragiles Scrollen direkt antippbar (siehe group_watchlist_ui_test.dart).
      addTearDown(tester.view.resetPhysicalSize);
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;

      final container = await _readyContainer(
        firestore: firestore,
        auth: auth,
        tmdbService: _tmdbService(providers: {8: 'Netflix'}),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: MovieFilterScreen(groupId: groupId)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Netflix'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Anwenden'));
      await tester.pumpAndSettle();

      final filter = container.read(movieFilterControllerProvider(groupId));
      expect(filter.watchProviderId, 8);
      expect(filter.isActive, isTrue);
    });

    testWidgets('mehrere Genres können gleichzeitig ausgewählt werden (Mehrfachauswahl)',
        (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;

      final container = await _readyContainer(
        firestore: firestore,
        auth: auth,
        tmdbService: _tmdbService(genres: {28: 'Action', 12: 'Abenteuer'}),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: MovieFilterScreen(groupId: groupId)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Action'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abenteuer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Anwenden'));
      await tester.pumpAndSettle();

      final filter = container.read(movieFilterControllerProvider(groupId));
      expect(filter.genreIds, {28, 12});
    });

    testWidgets('Zurücksetzen ist deaktiviert ohne aktiven Filter und leert einen bestehenden Filter',
        (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;

      final container = await _readyContainer(
        firestore: firestore,
        auth: auth,
        tmdbService: _tmdbService(providers: {8: 'Netflix'}),
      );
      addTearDown(container.dispose);
      container
          .read(movieFilterControllerProvider(groupId).notifier)
          .update(const MovieFilter(watchProviderId: 8));

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: MovieFilterScreen(groupId: groupId)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Zurücksetzen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Anwenden'));
      await tester.pumpAndSettle();

      final filter = container.read(movieFilterControllerProvider(groupId));
      expect(filter.isActive, isFalse);
    });

    testWidgets('Abbrechen (Zurück) verwirft die Auswahl, ohne den aktiven Filter zu verändern',
        (tester) async {
      final container = await _readyContainer(
        firestore: firestore,
        auth: auth,
        tmdbService: _tmdbService(providers: {8: 'Netflix', 9: 'Amazon Prime Video'}),
      );
      addTearDown(container.dispose);

      // MovieFilterScreen wird über einen echten Push geöffnet (statt als
      // `home`), damit ein echter Zurück-Button existiert, den `pageBack()`
      // finden kann.
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => MovieFilterScreen(groupId: groupId)),
                    ),
                    child: const Text('Öffnen'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Öffnen'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Netflix'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      final filter = container.read(movieFilterControllerProvider(groupId));
      expect(filter.isActive, isFalse);
    });

    testWidgets('TMDB-Fehler beim Laden der Plattformen blockiert nicht den Rest der Filterseite',
        (tester) async {
      final client = MockClient((request) async {
        if (request.url.path.contains('/watch/providers/movie')) {
          return http.Response('{}', 500);
        }
        if (request.url.path.contains('/genre/movie/list')) {
          return http.Response(
            jsonEncode({
              'genres': [
                {'id': 28, 'name': 'Action'},
              ],
            }),
            200,
          );
        }
        return http.Response('{}', 404);
      });
      final container = await _readyContainer(
        firestore: firestore,
        auth: auth,
        tmdbService: TmdbService(client, accessToken: 'test-token'),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: MovieFilterScreen(groupId: groupId)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Action'), findsOneWidget);
    });
  });

  group('GroupSwipeScreen - Filter-Button', () {
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

    testWidgets('Filter-Icon öffnet den MovieFilterScreen der aktuellen Gruppe', (tester) async {
      final container = await _readyContainer(
        firestore: firestore,
        auth: auth,
        tmdbService: _tmdbService(movies: {100: 'Film A'}),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: GroupSwipeScreen(groupId: groupId)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.tune));
      await tester.pumpAndSettle();

      final filterScreen = tester.widget<MovieFilterScreen>(find.byType(MovieFilterScreen));
      expect(filterScreen.groupId, groupId);
    });

    testWidgets('zeigt kein Badge ohne aktiven Filter, aber die Anzahl bei aktivem Filter',
        (tester) async {
      final container = await _readyContainer(
        firestore: firestore,
        auth: auth,
        tmdbService: _tmdbService(movies: {100: 'Film A'}),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: GroupSwipeScreen(groupId: groupId)),
        ),
      );
      await tester.pumpAndSettle();

      var badge = tester.widget<Badge>(find.byType(Badge));
      expect(badge.isLabelVisible, isFalse);

      container
          .read(movieFilterControllerProvider(groupId).notifier)
          .update(const MovieFilter(watchProviderId: 8, genreIds: {28}));
      await tester.pumpAndSettle();

      badge = tester.widget<Badge>(find.byType(Badge));
      expect(badge.isLabelVisible, isTrue);
      expect(find.text('2'), findsOneWidget);
    });
  });
}
