import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:film2watch/models/movie_swipe.dart';
import 'package:film2watch/models/user_statistics.dart';
import 'package:film2watch/providers/auth_provider.dart';
import 'package:film2watch/providers/statistics_provider.dart';
import 'package:film2watch/repositories/group_repository.dart';
import 'package:film2watch/repositories/swipe_repository.dart';
import 'package:film2watch/repositories/user_repository.dart';
import 'package:film2watch/screens/profile/profile_screen.dart';
import 'package:film2watch/screens/profile/statistics_screen.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StatisticsScreen (§15: Detaillierte Statistiken)', () {
    late FakeFirebaseFirestore firestore;
    late MockFirebaseAuth auth;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      auth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'alice', email: 'alice@film2watch.app'),
        signedIn: true,
      );
    });

    Widget wrap() {
      return ProviderScope(
        overrides: [
          firebaseAuthProvider.overrideWithValue(auth),
          firestoreProvider.overrideWithValue(firestore),
        ],
        child: const MaterialApp(home: StatisticsScreen()),
      );
    }

    testWidgets('zeigt einen Upsell-Hinweis statt Daten für einen Free-User', (tester) async {
      // Kein premium_status-Dokument - Normalfall für einen Free-User.
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      expect(find.text('Statistiken sind ein Premium-Feature.'), findsOneWidget);
      expect(find.text('Swipes'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('zeigt einen Ladezustand, solange der Premium-Status noch nicht bestätigt ist',
        (tester) async {
      await tester.pumpWidget(wrap());
      // Kein pumpAndSettle: der erste Frame vor Auflösung des Premium-Status.
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Statistiken sind ein Premium-Feature.'), findsNothing);
    });

    testWidgets('zeigt einen ehrlichen Empty State für einen Premium-User ohne Aktivität',
        (tester) async {
      await firestore.collection('premium_status').doc('alice').set({'is_premium': true});

      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Noch keine Daten'),
        findsOneWidget,
      );
      expect(find.text('Swipes'), findsNothing);
    });

    testWidgets('zeigt die echten Kennzahlen für einen Premium-User mit Aktivität', (tester) async {
      await firestore.collection('premium_status').doc('alice').set({'is_premium': true});
      final group = await GroupRepository(firestore).createGroup(
        name: 'Filmabend',
        creatorUid: 'alice',
      );
      final swipeRepository = SwipeRepository(firestore);
      await swipeRepository.setSwipe(
        groupId: group.id,
        uid: 'alice',
        movieId: 1,
        decision: SwipeDecision.like,
      );
      await swipeRepository.setSwipe(
        groupId: group.id,
        uid: 'alice',
        movieId: 2,
        decision: SwipeDecision.like,
      );
      await swipeRepository.setSwipe(
        groupId: group.id,
        uid: 'alice',
        movieId: 3,
        decision: SwipeDecision.dislike,
      );
      await firestore.collection('groups').doc(group.id).collection('matches').doc('1').set({
        'movie_id': 1,
        'member_uids': ['alice'],
        'matched_at': Timestamp.now(),
      });

      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      expect(find.text('Swipes'), findsOneWidget);
      expect(find.text('3'), findsOneWidget, reason: 'Gesamtzahl der Swipes');
      expect(find.text('2'), findsOneWidget, reason: 'Likes');
      expect(find.text('1'), findsWidgets, reason: 'Dislikes und Matches, jeweils 1');
    });

    testWidgets('zeigt einen Fehlerzustand, wenn die Statistik nicht geladen werden konnte',
        (tester) async {
      await firestore.collection('premium_status').doc('alice').set({'is_premium': true});

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firebaseAuthProvider.overrideWithValue(auth),
            firestoreProvider.overrideWithValue(firestore),
            userStatisticsProvider.overrideWith((ref) => Future<UserStatistics>.error('boom')),
          ],
          child: const MaterialApp(home: StatisticsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Statistiken konnten nicht geladen werden.'), findsOneWidget);
    });
  });

  group('Navigation zur Statistik-Ansicht (aus dem Profil)', () {
    testWidgets('ein Tap auf "Statistiken" im Profil öffnet die StatisticsScreen', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'alice', email: 'alice@film2watch.app'),
        signedIn: true,
      );
      await UserRepository(firestore).ensureUserDocument(
        uid: 'alice',
        email: 'alice@film2watch.app',
        name: 'Alice',
      );

      // Größerer Viewport, damit die "Statistiken"-Sektion (unterhalb der
      // Freundesliste) im Test tatsächlich gebaut/sichtbar ist - `ListView`
      // baut/hält nur Kinder innerhalb (bzw. nahe) des Viewports, analog zum
      // bestehenden Muster in `group_watchlist_ui_test.dart`.
      addTearDown(tester.view.resetPhysicalSize);
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firebaseAuthProvider.overrideWithValue(auth),
            firestoreProvider.overrideWithValue(firestore),
          ],
          child: const MaterialApp(home: ProfileScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Statistiken'), findsOneWidget);
      await tester.tap(find.text('Statistiken'));
      await tester.pumpAndSettle();

      expect(find.byType(StatisticsScreen), findsOneWidget);
      expect(find.text('Statistiken sind ein Premium-Feature.'), findsOneWidget);
    });
  });
}
