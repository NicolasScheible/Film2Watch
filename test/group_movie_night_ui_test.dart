import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:film2watch/providers/auth_provider.dart';
import 'package:film2watch/providers/tmdb_provider.dart';
import 'package:film2watch/repositories/group_repository.dart';
import 'package:film2watch/screens/groups/group_detail_screen.dart';
import 'package:film2watch/screens/groups/movie_night_form_screen.dart';
import 'package:film2watch/services/tmdb_service.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Discover liefert leer, `/genre/movie/list` leer, `/watch/providers/movie`
/// liefert [providers] (id -> Name) - Grundlage für die Plattform-Auswahl im
/// Filmabend-Formular. Löst nie echte HTTP-Requests aus.
TmdbService _tmdbService({Map<int, String> providers = const {8: 'Netflix', 9: 'Disney+'}}) {
  final client = MockClient((request) async {
    if (request.url.path.contains('/genre/movie/list')) {
      return http.Response(jsonEncode({'genres': <dynamic>[]}), 200);
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
      return http.Response(
        jsonEncode({'page': 1, 'total_pages': 1, 'total_results': 0, 'results': <dynamic>[]}),
        200,
      );
    }
    return http.Response('{}', 404);
  });
  return TmdbService(client, accessToken: 'test-token');
}

/// Vergrößert die Test-Viewport-Höhe, damit die neue "Filmabende"-Sektion
/// (unterhalb von Matches/Watchlist) und das Formular ohne manuelles
/// Scrollen antippbar sind - vermeidet die Mehrdeutigkeit mehrerer
/// gleichzeitig gemounteter `Scrollable`s (altes + neues Navigator-Route),
/// die `tester.scrollUntilVisible` in diesem Szenario nicht zuverlässig
/// auflösen kann.
Future<void> _useTallViewport(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  group('Filmabend-UI (§12: "Filmabend planen")', () {
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
        name: 'Filmabend-Gruppe',
        creatorUid: 'alice',
      );
      groupId = group.id;
    });

    Widget wrap(Widget child) {
      return ProviderScope(
        overrides: [
          firebaseAuthProvider.overrideWithValue(auth),
          firestoreProvider.overrideWithValue(firestore),
          tmdbServiceProvider.overrideWithValue(_tmdbService()),
        ],
        child: MaterialApp(home: child),
      );
    }

    testWidgets('zeigt einen ehrlichen Empty State, wenn noch kein Filmabend geplant ist', (tester) async {
      await _useTallViewport(tester);
      await tester.pumpWidget(wrap(GroupDetailScreen(groupId: groupId)));
      await tester.pumpAndSettle();

      expect(find.text('Noch kein Filmabend geplant.'), findsOneWidget);
    });

    testWidgets('Filmabend planen: Formular anlegen, Plattform wählen, speichern zeigt den Filmabend in der Liste',
        (tester) async {
      await _useTallViewport(tester);
      await tester.pumpWidget(wrap(GroupDetailScreen(groupId: groupId)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Planen'));
      await tester.pumpAndSettle();
      expect(find.byType(MovieNightFormScreen), findsOneWidget);

      await tester.tap(find.text('Netflix'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Filmabend planen'));
      await tester.pumpAndSettle();

      // Formular schließt sich nach Erfolg automatisch.
      expect(find.byType(MovieNightFormScreen), findsNothing);
      final docs = await firestore.collection('groups').doc(groupId).collection('movie_nights').get();
      expect(docs.docs, hasLength(1));
      expect(docs.docs.first.data()['platform_id'], 8);
      expect(docs.docs.first.data()['created_by'], 'alice');
    });

    testWidgets('ohne gewählte Plattform wird nichts gespeichert (Validierung)', (tester) async {
      await _useTallViewport(tester);
      await tester.pumpWidget(wrap(MovieNightFormScreen(groupId: groupId)));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Filmabend planen'));
      await tester.pumpAndSettle();

      expect(find.text('Bitte wähle eine Plattform aus.'), findsOneWidget);
      final docs = await firestore.collection('groups').doc(groupId).collection('movie_nights').get();
      expect(docs.docs, isEmpty);
    });

    testWidgets('der Ersteller kann seinen eigenen Filmabend bearbeiten (Tap öffnet das Formular vorausgefüllt)',
        (tester) async {
      await _useTallViewport(tester);
      await firestore.collection('groups').doc(groupId).collection('movie_nights').add({
        'created_by': 'alice',
        'created_at': Timestamp.now(),
        'updated_at': Timestamp.now(),
        'scheduled_at': Timestamp.fromDate(DateTime(2026, 12, 24, 20)),
        'platform_id': 8,
      });

      await tester.pumpWidget(wrap(GroupDetailScreen(groupId: groupId)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Netflix'));
      await tester.pumpAndSettle();

      expect(find.byType(MovieNightFormScreen), findsOneWidget);
      expect(find.text('Filmabend bearbeiten'), findsOneWidget);
      expect(find.text('Filmabend absagen'), findsOneWidget);
    });

    testWidgets('ein normales, fremdes Mitglied kann einen fremden Filmabend nicht antippen (kein Formular-Zugriff)',
        (tester) async {
      await _useTallViewport(tester);
      await firestore
          .collection('groups')
          .doc(groupId)
          .collection('members')
          .doc('bob')
          .set({'uid': 'bob', 'role': 'member', 'joined_at': Timestamp.now()});
      await firestore.collection('groups').doc(groupId).collection('movie_nights').add({
        'created_by': 'alice',
        'created_at': Timestamp.now(),
        'updated_at': Timestamp.now(),
        'scheduled_at': Timestamp.fromDate(DateTime(2026, 12, 24, 20)),
        'platform_id': 8,
      });

      final bobAuth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'bob', email: 'bob@film2watch.app'),
        signedIn: true,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firebaseAuthProvider.overrideWithValue(bobAuth),
            firestoreProvider.overrideWithValue(firestore),
            tmdbServiceProvider.overrideWithValue(_tmdbService()),
          ],
          child: MaterialApp(home: GroupDetailScreen(groupId: groupId)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Netflix'));
      await tester.pumpAndSettle();

      expect(find.byType(MovieNightFormScreen), findsNothing);
    });

    testWidgets('Absagen mit Bestätigung entfernt den Filmabend', (tester) async {
      await _useTallViewport(tester);
      final ref = await firestore.collection('groups').doc(groupId).collection('movie_nights').add({
        'created_by': 'alice',
        'created_at': Timestamp.now(),
        'updated_at': Timestamp.now(),
        'scheduled_at': Timestamp.fromDate(DateTime(2026, 12, 24, 20)),
        'platform_id': 8,
      });

      await tester.pumpWidget(wrap(GroupDetailScreen(groupId: groupId)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Netflix'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Filmabend absagen'));
      await tester.pumpAndSettle();
      expect(find.text('Möchtest du diesen Filmabend wirklich absagen?'), findsOneWidget);

      await tester.tap(find.text('Absagen'));
      await tester.pumpAndSettle();

      expect(find.byType(MovieNightFormScreen), findsNothing);
      expect((await ref.get()).exists, isFalse);
    });

    testWidgets('Absagen abbrechen lässt den Filmabend unverändert bestehen', (tester) async {
      await _useTallViewport(tester);
      final ref = await firestore.collection('groups').doc(groupId).collection('movie_nights').add({
        'created_by': 'alice',
        'created_at': Timestamp.now(),
        'updated_at': Timestamp.now(),
        'scheduled_at': Timestamp.fromDate(DateTime(2026, 12, 24, 20)),
        'platform_id': 8,
      });

      await tester.pumpWidget(wrap(GroupDetailScreen(groupId: groupId)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Netflix'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Filmabend absagen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Zurück'));
      await tester.pumpAndSettle();

      expect(find.byType(MovieNightFormScreen), findsOneWidget);
      expect((await ref.get()).exists, isTrue);
    });
  });
}
