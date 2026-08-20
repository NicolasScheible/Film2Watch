import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:film2watch/providers/auth_provider.dart';
import 'package:film2watch/providers/chat_provider.dart';
import 'package:film2watch/repositories/chat_repository.dart';
import 'package:film2watch/repositories/group_repository.dart';
import 'package:film2watch/screens/groups/group_chat_screen.dart';
import 'package:film2watch/services/chat_service.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Verzögertes [ChatService], um den Loading-/Disabled-Zustand während eines
/// laufenden Sendevorgangs deterministisch beobachten zu können (analog zum
/// `_DelayedAuthService`-Muster in `widget_test.dart`).
class _DelayedChatService extends ChatService {
  _DelayedChatService(super.chatRepository, super.groupRepository);

  @override
  Future<void> sendMessage({
    required String groupId,
    required String senderUid,
    required String text,
  }) async {
    await Future.delayed(const Duration(milliseconds: 100));
    await super.sendMessage(groupId: groupId, senderUid: senderUid, text: text);
  }
}

Future<String> _seedGroup(FakeFirebaseFirestore firestore, {String selfUid = 'alice'}) async {
  final groupRepository = GroupRepository(firestore);
  final group = await groupRepository.createGroup(name: 'Filmabend', creatorUid: selfUid);
  return group.id;
}

Align _alignOf(WidgetTester tester, String text) {
  return tester.widget<Align>(
    find.ancestor(of: find.text(text), matching: find.byType(Align)).first,
  );
}

void main() {
  group('Gruppenchat UI', () {
    testWidgets('zeigt einen ehrlichen Empty State, wenn noch keine Nachrichten existieren',
        (tester) async {
      final firestore = FakeFirebaseFirestore();
      final groupId = await _seedGroup(firestore);
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
          child: MaterialApp(home: GroupChatScreen(groupId: groupId)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Noch keine Nachrichten.'), findsOneWidget);
    });

    testWidgets('eigene Nachricht erscheint rechts, fremde Nachricht links mit Avatar/Name',
        (tester) async {
      final firestore = FakeFirebaseFirestore();
      final groupId = await _seedGroup(firestore);
      await GroupRepository(firestore).acceptInvitation(groupId: groupId, inviteeUid: 'bob');
      await UserRepositoryHelper.ensurePublicProfile(firestore, uid: 'bob', name: 'Bob');
      await ChatRepository(firestore).sendMessage(groupId: groupId, senderUid: 'alice', text: 'Meine Nachricht');
      await ChatRepository(firestore).sendMessage(groupId: groupId, senderUid: 'bob', text: 'Bobs Nachricht');

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
          child: MaterialApp(home: GroupChatScreen(groupId: groupId)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Meine Nachricht'), findsOneWidget);
      expect(find.text('Bobs Nachricht'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(_alignOf(tester, 'Meine Nachricht').alignment, Alignment.centerRight);
      expect(_alignOf(tester, 'Bobs Nachricht').alignment, Alignment.centerLeft);
    });

    testWidgets('Eingabe, Senden, Loading und erfolgreiche Nachricht', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final groupId = await _seedGroup(firestore);
      final auth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'alice', email: 'alice@film2watch.app'),
        signedIn: true,
      );
      final delayedService = _DelayedChatService(
        ChatRepository(firestore),
        GroupRepository(firestore),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firebaseAuthProvider.overrideWithValue(auth),
            firestoreProvider.overrideWithValue(firestore),
            chatServiceProvider.overrideWithValue(delayedService),
          ],
          child: MaterialApp(home: GroupChatScreen(groupId: groupId)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Testnachricht');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();

      // Während des (künstlich verzögerten) Sendevorgangs: Ladeindikator
      // statt Senden-Icon, Eingabefeld deaktiviert (kein Doppel-Senden).
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.send), findsNothing);
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.enabled, isFalse);
      // Eingabefeld wird direkt beim Absenden geleert (kein Warten auf den
      // Server nötig, damit der Nutzer sofort weiterschreiben kann).
      expect(find.text('Testnachricht'), findsNothing);

      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Testnachricht'), findsOneWidget);
    });

    testWidgets('zeigt einen Fehler, wenn das Senden fehlschlägt', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final groupId = await _seedGroup(firestore);
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
          child: MaterialApp(home: GroupChatScreen(groupId: groupId)),
        ),
      );
      await tester.pumpAndSettle();

      // Whitespace-only wird clientseitig durch `_send()` bereits
      // abgefangen (kein Request) - für einen echten Server-/Service-Fehler
      // wird hier ein Text über die maximale Länge hinaus gesendet.
      await tester.enterText(find.byType(TextField), 'x' * (chatMaxMessageLength + 1));
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      expect(find.textContaining('zu lang'), findsOneWidget);
    });
  });
}

/// Kleiner Test-Helfer: legt ein öffentliches Profil an, damit
/// `MessageBubble` bei fremden Nachrichten einen echten Namen anzeigen kann.
abstract final class UserRepositoryHelper {
  static Future<void> ensurePublicProfile(
    FakeFirebaseFirestore firestore, {
    required String uid,
    required String name,
  }) {
    return firestore.collection('public_profiles').doc(uid).set({
      'uid': uid,
      'name': name,
      'profile_picture': null,
      'friend_code': 'FILM-0000',
    });
  }
}
