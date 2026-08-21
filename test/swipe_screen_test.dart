import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:film2watch/providers/auth_provider.dart';
import 'package:film2watch/repositories/group_repository.dart';
import 'package:film2watch/screens/groups/group_swipe_screen.dart';
import 'package:film2watch/screens/swipe/swipe_screen.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SwipeScreen (zentraler Einstieg)', () {
    testWidgets('zeigt einen ehrlichen Empty State, wenn der Nutzer in keiner Gruppe ist',
        (tester) async {
      final firestore = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'alice', email: 'alice@film2watch.app'),
        signedIn: true,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firebaseAuthProvider.overrideWithValue(auth),
            firestoreProvider.overrideWithValue(firestore),
          ],
          child: const MaterialApp(home: SwipeScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Tritt einer Gruppe bei, um dort Filme zu swipen.'), findsOneWidget);
    });

    testWidgets('zeigt die Gruppen des Nutzers und öffnet beim Antippen den echten GroupSwipeScreen der Gruppe',
        (tester) async {
      final firestore = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'alice', email: 'alice@film2watch.app'),
        signedIn: true,
      );
      final group = await GroupRepository(firestore).createGroup(name: 'Filmabend', creatorUid: 'alice');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firebaseAuthProvider.overrideWithValue(auth),
            firestoreProvider.overrideWithValue(firestore),
          ],
          child: const MaterialApp(home: SwipeScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Filmabend'), findsOneWidget);
      expect(find.text('Tritt einer Gruppe bei, um dort Filme zu swipen.'), findsNothing);

      await tester.tap(find.text('Filmabend'));
      await tester.pumpAndSettle();

      final swipeScreen = tester.widget<GroupSwipeScreen>(find.byType(GroupSwipeScreen));
      expect(swipeScreen.groupId, group.id);
    });

    testWidgets('zeigt mehrere Gruppen unabhängig voneinander an', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'alice', email: 'alice@film2watch.app'),
        signedIn: true,
      );
      await GroupRepository(firestore).createGroup(name: 'Freitag Filmabend', creatorUid: 'alice');
      await GroupRepository(firestore).createGroup(name: 'WG-Kino', creatorUid: 'alice');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firebaseAuthProvider.overrideWithValue(auth),
            firestoreProvider.overrideWithValue(firestore),
          ],
          child: const MaterialApp(home: SwipeScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Freitag Filmabend'), findsOneWidget);
      expect(find.text('WG-Kino'), findsOneWidget);
    });
  });
}
