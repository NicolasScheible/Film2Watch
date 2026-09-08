import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:film2watch/components/movies/movie_poll_card.dart';
import 'package:film2watch/providers/auth_provider.dart';
import 'package:film2watch/providers/tmdb_provider.dart';
import 'package:film2watch/repositories/group_repository.dart';
import 'package:film2watch/screens/groups/group_detail_screen.dart';
import 'package:film2watch/screens/groups/movie_poll_detail_screen.dart';
import 'package:film2watch/screens/groups/movie_poll_form_screen.dart';
import 'package:film2watch/services/tmdb_service.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// `/watch/providers/movie` liefert [providers] (id -> Name);
/// `/genre/movie/list`/`/discover/movie` liefern immer leere Ergebnisse
/// (für diese Screens nicht relevant). Löst nie echte HTTP-Requests aus.
TmdbService _tmdbService({Map<int, String> providers = const {}}) {
  final client = MockClient((request) async {
    if (request.url.path.contains('/watch/providers/movie')) {
      final entries = providers.entries
          .map((e) => '{"provider_id": ${e.key}, "provider_name": "${e.value}", "logo_path": null}')
          .join(',');
      return http.Response('{"results": [$entries]}', 200);
    }
    if (request.url.path.contains('/genre/movie/list')) {
      return http.Response('{"genres": []}', 200);
    }
    return http.Response('{"page": 1, "total_pages": 1, "total_results": 0, "results": []}', 200);
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
  group('MoviePollFormScreen', () {
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

    testWidgets('erstellt eine Abstimmung mit den zwei Standard-Terminvorschlägen', (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      tester.view.physicalSize = const Size(800, 2600);
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
          child: MaterialApp(home: MoviePollFormScreen(groupId: groupId)),
        ),
      );
      await tester.pumpAndSettle();

      final netflixChips = find.text('Netflix');
      expect(netflixChips, findsNWidgets(2));
      await tester.tap(netflixChips.first);
      await tester.pumpAndSettle();
      await tester.tap(netflixChips.last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Abstimmung starten'));
      await tester.pumpAndSettle();

      final polls = await firestore.collection('groups/$groupId/movie_night_polls').get();
      expect(polls.docs, hasLength(1));
      final options = await firestore
          .collection('groups/$groupId/movie_night_polls/${polls.docs.first.id}/options')
          .get();
      expect(options.docs, hasLength(2));
      for (final option in options.docs) {
        expect(option.data()['platform_id'], 8);
      }
    });

    testWidgets('lehnt das Absenden ab, solange nicht jeder Terminvorschlag eine Plattform hat',
        (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      tester.view.physicalSize = const Size(800, 2600);
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
          child: MaterialApp(home: MoviePollFormScreen(groupId: groupId)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Abstimmung starten'));
      await tester.pumpAndSettle();

      expect(
        find.text('Bitte wähle für jeden Terminvorschlag eine Plattform aus.'),
        findsOneWidget,
      );
      expect((await firestore.collection('groups/$groupId/movie_night_polls').get()).docs, isEmpty);
    });

    testWidgets('ein weiterer Terminvorschlag kann hinzugefügt und wieder entfernt werden', (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      tester.view.physicalSize = const Size(800, 3200);
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
          child: MaterialApp(home: MoviePollFormScreen(groupId: groupId)),
        ),
      );
      await tester.pumpAndSettle();

      // Bei genau 2 Optionen (dem Minimum) gibt es noch keinen
      // Entfernen-Button.
      expect(find.byIcon(Icons.close), findsNothing);

      await tester.tap(find.text('Terminvorschlag hinzufügen'));
      await tester.pumpAndSettle();

      expect(find.text('Netflix'), findsNWidgets(3));
      expect(find.byIcon(Icons.close), findsNWidgets(3));

      await tester.tap(find.byIcon(Icons.close).first);
      await tester.pumpAndSettle();

      expect(find.text('Netflix'), findsNWidgets(2));
      expect(find.byIcon(Icons.close), findsNothing);
    });
  });

  group('GroupDetailScreen - Abstimmungen', () {
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

    testWidgets('zeigt einen ehrlichen Empty State ohne Abstimmung und öffnet das Formular', (tester) async {
      final container = await _readyContainer(
        firestore: firestore,
        auth: auth,
        tmdbService: _tmdbService(),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: GroupDetailScreen(groupId: groupId)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Noch keine Abstimmung gestartet.'), findsOneWidget);

      await tester.tap(find.text('Neue Abstimmung'));
      await tester.pumpAndSettle();

      expect(find.byType(MoviePollFormScreen), findsOneWidget);
    });

    testWidgets('zeigt eine bestehende, offene Abstimmung als Karte', (tester) async {
      final pollRef = firestore.collection('groups/$groupId/movie_night_polls').doc('poll1');
      await pollRef.set({
        'created_by': 'alice',
        'created_at': Timestamp.now(),
        'deadline': Timestamp.fromDate(DateTime.now().add(const Duration(days: 3))),
        'status': 'open',
      });
      await pollRef.collection('options').doc('opt1').set({
        'scheduled_at': Timestamp.now(),
        'platform_id': 8,
      });

      final container = await _readyContainer(
        firestore: firestore,
        auth: auth,
        tmdbService: _tmdbService(),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: GroupDetailScreen(groupId: groupId)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1 Terminvorschläge'), findsOneWidget);

      await tester.tap(find.byType(MoviePollCard));
      await tester.pumpAndSettle();

      expect(find.byType(MoviePollDetailScreen), findsOneWidget);
    });
  });

  group('MoviePollDetailScreen', () {
    late FakeFirebaseFirestore firestore;
    late MockFirebaseAuth auth;
    late String groupId;
    late String pollId;
    late String optionAId;
    late String optionBId;

    setUp(() async {
      firestore = FakeFirebaseFirestore();
      auth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'alice', email: 'alice@film2watch.app'),
        signedIn: true,
      );
      final group = await GroupRepository(firestore).createGroup(name: 'Filmabend', creatorUid: 'alice');
      groupId = group.id;
      await firestore
          .collection('groups')
          .doc(groupId)
          .collection('members')
          .doc('bob')
          .set({'uid': 'bob', 'role': 'member', 'joined_at': Timestamp.now()});

      final pollRef = firestore.collection('groups/$groupId/movie_night_polls').doc();
      pollId = pollRef.id;
      await pollRef.set({
        'created_by': 'alice',
        'created_at': Timestamp.now(),
        'deadline': Timestamp.fromDate(DateTime.now().add(const Duration(days: 3))),
        'status': 'open',
      });
      final optionA = pollRef.collection('options').doc();
      optionAId = optionA.id;
      await optionA.set({'scheduled_at': Timestamp.now(), 'platform_id': 8});
      final optionB = pollRef.collection('options').doc();
      optionBId = optionB.id;
      await optionB.set({'scheduled_at': Timestamp.now(), 'platform_id': 9});
    });

    testWidgets('ein Mitglied kann mehrere Terminvorschläge gleichzeitig auswählen (Doodle-Prinzip)',
        (tester) async {
      final container = await _readyContainer(
        firestore: firestore,
        auth: auth,
        tmdbService: _tmdbService(providers: {8: 'Netflix', 9: 'Amazon Prime Video'}),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: MoviePollDetailScreen(groupId: groupId, pollId: pollId)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Netflix'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Amazon Prime Video'));
      await tester.pumpAndSettle();

      final votes = await firestore.collection('groups/$groupId/movie_night_polls/$pollId/votes').get();
      expect(votes.docs.map((d) => d.data()['option_id']).toSet(), {optionAId, optionBId});
      expect(find.text('1 Stimme'), findsNWidgets(2));
    });

    testWidgets('ein erneutes Antippen entfernt die eigene Stimme wieder', (tester) async {
      final container = await _readyContainer(
        firestore: firestore,
        auth: auth,
        tmdbService: _tmdbService(providers: {8: 'Netflix', 9: 'Amazon Prime Video'}),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: MoviePollDetailScreen(groupId: groupId, pollId: pollId)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Netflix'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Netflix'));
      await tester.pumpAndSettle();

      final votes = await firestore.collection('groups/$groupId/movie_night_polls/$pollId/votes').get();
      expect(votes.docs, isEmpty);
    });

    testWidgets('zeigt die Stimmen anderer Mitglieder live an', (tester) async {
      await firestore
          .collection('groups/$groupId/movie_night_polls/$pollId/votes')
          .doc('bob_$optionAId')
          .set({'uid': 'bob', 'option_id': optionAId, 'voted_at': Timestamp.now()});

      final container = await _readyContainer(
        firestore: firestore,
        auth: auth,
        tmdbService: _tmdbService(providers: {8: 'Netflix', 9: 'Amazon Prime Video'}),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: MoviePollDetailScreen(groupId: groupId, pollId: pollId)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1 Stimme'), findsOneWidget);
      expect(find.text('0 Stimmen'), findsOneWidget);
    });

    testWidgets('zeigt nach Auswertung mit Gewinner das Ergebnis an und erlaubt kein weiteres Abstimmen',
        (tester) async {
      await firestore.collection('groups/$groupId/movie_night_polls').doc(pollId).update({
        'status': 'closed',
        'winning_option_id': optionAId,
        'result_movie_night_id': 'mn1',
        'resolved_at': Timestamp.now(),
      });

      final container = await _readyContainer(
        firestore: firestore,
        auth: auth,
        tmdbService: _tmdbService(providers: {8: 'Netflix', 9: 'Amazon Prime Video'}),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: MoviePollDetailScreen(groupId: groupId, pollId: pollId)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Die Abstimmung ist beendet.'), findsOneWidget);
      expect(
        find.text('Ergebnis: die Mehrheit hat sich entschieden - der Filmabend wurde geplant.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Netflix'));
      await tester.pumpAndSettle();

      final votes = await firestore.collection('groups/$groupId/movie_night_polls/$pollId/votes').get();
      expect(votes.docs, isEmpty);
    });

    testWidgets('zeigt nach Auswertung ohne Gewinner ehrlich an, dass niemand abgestimmt hat',
        (tester) async {
      await firestore.collection('groups/$groupId/movie_night_polls').doc(pollId).update({
        'status': 'closed',
        'winning_option_id': null,
        'result_movie_night_id': null,
        'resolved_at': Timestamp.now(),
      });

      final container = await _readyContainer(
        firestore: firestore,
        auth: auth,
        tmdbService: _tmdbService(providers: {8: 'Netflix', 9: 'Amazon Prime Video'}),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: MoviePollDetailScreen(groupId: groupId, pollId: pollId)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Niemand hat abgestimmt - es gibt kein Ergebnis.'), findsOneWidget);
    });
  });
}
