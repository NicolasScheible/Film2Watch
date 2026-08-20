import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:film2watch/providers/auth_provider.dart';
import 'package:film2watch/screens/onboarding/onboarding_screen.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OnboardingScreen', () {
    late FakeFirebaseFirestore firestore;
    late MockFirebaseAuth auth;
    late ProviderContainer container;

    setUp(() async {
      firestore = FakeFirebaseFirestore();
      auth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'alice', email: 'alice@film2watch.app'),
        signedIn: true,
      );
      await firestore.collection('users').doc('alice').set({
        'uid': 'alice',
        'name': 'Alice',
        'email': 'alice@film2watch.app',
        'profile_picture': null,
        'friend_code': 'FILM-1234',
        'created_at': Timestamp.now(),
        'onboarding_completed': false,
      });

      container = ProviderContainer(
        overrides: [
          firebaseAuthProvider.overrideWithValue(auth),
          firestoreProvider.overrideWithValue(firestore),
        ],
      );
      addTearDown(container.dispose);
      // `OnboardingScreen` liest `authStateChangesProvider` nur bei Bedarf
      // per `ref.read` (kein `ref.watch`) - ohne diese Vorwärmung wäre der
      // Provider beim ersten Lesen (im Tap-Handler) noch nicht aufgelöst und
      // `uid` fälschlich `null`, siehe `group_swipe_skip_test.dart` für die
      // ausführliche Begründung desselben Musters.
      container.listen(authStateChangesProvider, (previous, next) {});
      await container.read(authStateChangesProvider.future);
    });

    Widget wrap() {
      return UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: OnboardingScreen()),
      );
    }

    testWidgets('zeigt zuerst die Erklärung zu Like/Dislike', (tester) async {
      await tester.pumpWidget(wrap());

      expect(find.text('Rechts oder links wischen'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Weiter'), findsOneWidget);
    });

    testWidgets('führt durch alle drei Folien und zeigt auf der letzten "Los geht\'s"',
        (tester) async {
      await tester.pumpWidget(wrap());

      await tester.tap(find.widgetWithText(FilledButton, 'Weiter'));
      await tester.pumpAndSettle();
      expect(find.text('Vielleicht später?'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Weiter'));
      await tester.pumpAndSettle();
      expect(find.text('Freunde per Code hinzufügen'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Los geht\'s'), findsOneWidget);
    });

    testWidgets('"Los geht\'s" auf der letzten Folie speichert den Abschluss', (tester) async {
      await tester.pumpWidget(wrap());

      await tester.tap(find.widgetWithText(FilledButton, 'Weiter'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Weiter'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Los geht\'s'));
      await tester.pumpAndSettle();

      final doc = await firestore.collection('users').doc('alice').get();
      expect(doc.data()!['onboarding_completed'], isTrue);
    });

    testWidgets('"Überspringen" speichert den Abschluss sofort, ohne alle Folien zu durchlaufen',
        (tester) async {
      await tester.pumpWidget(wrap());

      await tester.tap(find.text('Überspringen'));
      await tester.pumpAndSettle();

      final doc = await firestore.collection('users').doc('alice').get();
      expect(doc.data()!['onboarding_completed'], isTrue);
    });
  });
}
