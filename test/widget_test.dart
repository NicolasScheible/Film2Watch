import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:film2watch/app.dart';
import 'package:film2watch/providers/auth_form_controller.dart';
import 'package:film2watch/providers/auth_provider.dart';
import 'package:film2watch/repositories/auth_repository.dart';
import 'package:film2watch/repositories/user_repository.dart';
import 'package:film2watch/screens/app_gate.dart';
import 'package:film2watch/services/auth_service.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppGate', () {
    testWidgets('zeigt den Auth Screen, wenn kein User eingeloggt ist', (tester) async {
      final mockAuth = MockFirebaseAuth(signedIn: false);
      final fakeFirestore = FakeFirebaseFirestore();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firebaseAuthProvider.overrideWithValue(mockAuth),
            firestoreProvider.overrideWithValue(fakeFirestore),
          ],
          child: const MaterialApp(home: AppGate()),
        ),
      );
      await tester.pump();

      expect(find.text('Willkommen zurück'), findsOneWidget);
      expect(find.text('Swipe'), findsNothing);
    });

    testWidgets(
        'zeigt die Haupt-App, wenn ein User mit vollständigem Profil und abgeschlossenem Onboarding eingeloggt ist',
        (tester) async {
      final mockUser = MockUser(
        uid: 'uid-1',
        email: 'nico@film2watch.app',
        displayName: 'Nico',
      );
      final mockAuth = MockFirebaseAuth(mockUser: mockUser, signedIn: true);
      final fakeFirestore = FakeFirebaseFirestore();
      await fakeFirestore.collection('users').doc('uid-1').set({
        'uid': 'uid-1',
        'name': 'Nico',
        'email': 'nico@film2watch.app',
        'profile_picture': null,
        'friend_code': 'FILM-1234',
        'created_at': Timestamp.now(),
        'onboarding_completed': true,
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firebaseAuthProvider.overrideWithValue(mockAuth),
            firestoreProvider.overrideWithValue(fakeFirestore),
          ],
          child: const MaterialApp(home: AppGate()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Swipe'), findsWidgets);
      expect(find.text('Willkommen zurück'), findsNothing);
    });

    testWidgets(
        'zeigt das Onboarding-Tutorial statt der Haupt-App, wenn der User es noch nicht abgeschlossen hat',
        (tester) async {
      final mockUser = MockUser(
        uid: 'uid-2',
        email: 'neu@film2watch.app',
        displayName: 'Neu',
      );
      final mockAuth = MockFirebaseAuth(mockUser: mockUser, signedIn: true);
      final fakeFirestore = FakeFirebaseFirestore();
      await fakeFirestore.collection('users').doc('uid-2').set({
        'uid': 'uid-2',
        'name': 'Neu',
        'email': 'neu@film2watch.app',
        'profile_picture': null,
        'friend_code': 'FILM-5678',
        'created_at': Timestamp.now(),
        'onboarding_completed': false,
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firebaseAuthProvider.overrideWithValue(mockAuth),
            firestoreProvider.overrideWithValue(fakeFirestore),
          ],
          child: const MaterialApp(home: AppGate()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Rechts oder links wischen'), findsOneWidget);
      expect(find.text('Swipe'), findsNothing);
    });

    testWidgets('wechselt nach Abschluss des Onboardings automatisch zur Haupt-App', (tester) async {
      final mockUser = MockUser(
        uid: 'uid-3',
        email: 'neu3@film2watch.app',
        displayName: 'Neu',
      );
      final mockAuth = MockFirebaseAuth(mockUser: mockUser, signedIn: true);
      final fakeFirestore = FakeFirebaseFirestore();
      await fakeFirestore.collection('users').doc('uid-3').set({
        'uid': 'uid-3',
        'name': 'Neu',
        'email': 'neu3@film2watch.app',
        'profile_picture': null,
        'friend_code': 'FILM-9012',
        'created_at': Timestamp.now(),
        'onboarding_completed': false,
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firebaseAuthProvider.overrideWithValue(mockAuth),
            firestoreProvider.overrideWithValue(fakeFirestore),
          ],
          child: const MaterialApp(home: AppGate()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Rechts oder links wischen'), findsOneWidget);

      await tester.tap(find.text('Überspringen'));
      await tester.pumpAndSettle();

      expect(find.text('Swipe'), findsWidgets);
      expect(find.text('Rechts oder links wischen'), findsNothing);
    });
  });

  group('AuthScreen', () {
    testWidgets('wechselt zwischen Login und Registrierung', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: Film2WatchApp())),
      );
      await tester.pump();

      expect(find.text('Willkommen zurück'), findsOneWidget);

      await tester.tap(find.text('Noch keinen Account? Jetzt registrieren'));
      await tester.pumpAndSettle();

      expect(find.text('Account erstellen'), findsWidgets);

      await tester.tap(find.text('Du hast schon einen Account? Jetzt einloggen'));
      await tester.pumpAndSettle();

      expect(find.text('Willkommen zurück'), findsOneWidget);
    });

    testWidgets('validiert, dass die Passwortbestätigung übereinstimmt', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: Film2WatchApp())),
      );
      await tester.pump();
      await tester.tap(find.text('Noch keinen Account? Jetzt registrieren'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Nico');
      await tester.enterText(find.widgetWithText(TextFormField, 'E-Mail'), 'nico@film2watch.app');
      await tester.enterText(find.widgetWithText(TextFormField, 'Passwort'), 'geheim123');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Passwort bestätigen'),
        'anders123',
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Account erstellen'));
      await tester.pumpAndSettle();

      expect(find.text('Die Passwörter stimmen nicht überein.'), findsOneWidget);
    });
  });

  group('AuthFormController', () {
    test('verhindert mehrfaches Absenden während eine Aktion lädt', () async {
      final fakeService = _DelayedAuthService();
      final container = ProviderContainer(
        overrides: [authServiceProvider.overrideWithValue(fakeService)],
      );
      addTearDown(container.dispose);

      final controller = container.read(authFormControllerProvider.notifier);
      await container.read(authFormControllerProvider.future);

      final first = controller.signInWithEmail(email: 'a@film2watch.app', password: '123456');
      final second = controller.signInWithEmail(email: 'a@film2watch.app', password: '123456');
      await Future.wait([first, second]);

      expect(fakeService.callCount, 1);
    });
  });
}

/// Fake für [AuthService], das die Firebase-Aufrufe künstlich verzögert, um
/// den Loading-State/Doppel-Submit-Schutz von [AuthFormController] zu testen,
/// ohne echte Firebase-Accounts anzulegen.
class _DelayedAuthService extends AuthService {
  _DelayedAuthService()
      : super(
          AuthRepository(MockFirebaseAuth()),
          UserRepository(FakeFirebaseFirestore()),
        );

  int callCount = 0;

  @override
  Future<void> signInWithEmail({required String email, required String password}) async {
    callCount++;
    await Future.delayed(const Duration(milliseconds: 100));
  }
}
