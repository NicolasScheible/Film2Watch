import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:film2watch/providers/auth_provider.dart';
import 'package:film2watch/providers/chat_provider.dart';
import 'package:film2watch/providers/chat_send_controller.dart';
import 'package:film2watch/providers/group_provider.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatSendController', () {
    late FakeFirebaseFirestore firestore;
    late ProviderContainer container;
    late String groupId;

    setUp(() async {
      firestore = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'alice', email: 'alice@film2watch.app'),
        signedIn: true,
      );
      container = ProviderContainer(
        overrides: [
          firebaseAuthProvider.overrideWithValue(auth),
          firestoreProvider.overrideWithValue(firestore),
        ],
      );
      addTearDown(container.dispose);
      // MockFirebaseAuth feuert sein initiales Sign-in-Event auf einem
      // Broadcast-Stream ohne Replay - der Listener muss deshalb im selben
      // synchronen Abschnitt registriert werden, noch vor jedem `await`.
      container.listen(authStateChangesProvider, (previous, next) {});
      await container.read(authStateChangesProvider.future);

      final group = await container.read(groupRepositoryProvider).createGroup(
            name: 'Filmabend',
            creatorUid: 'alice',
          );
      groupId = group.id;
      // Den (trivialen) Erstaufbau des Controllers abwarten, bevor Aktionen
      // ausgelöst werden - sonst würde der `state.isLoading`-Schutz gegen
      // Doppel-Submits fälschlich den noch laufenden Erstaufbau als "bereits
      // aktiv" werten und den allerersten Aufruf stillschweigend verwerfen.
      await container.read(chatSendControllerProvider(groupId).future);
    });

    test('Status landet im Erfolg nach erfolgreichem Senden', () async {
      final notifier = container.read(chatSendControllerProvider(groupId).notifier);

      await notifier.send('Hallo Gruppe!');

      expect(container.read(chatSendControllerProvider(groupId)).hasError, isFalse);
      final messages = await container.read(chatRepositoryProvider).watchLatestMessages(groupId).first;
      expect(messages.single.text, 'Hallo Gruppe!');
    });

    test('Status durchläuft Loading, bevor er im Erfolg landet', () async {
      final states = <bool>[];
      container.listen(
        chatSendControllerProvider(groupId),
        (previous, next) => states.add(next.isLoading),
        fireImmediately: true,
      );

      await container.read(chatSendControllerProvider(groupId).notifier).send('Test');

      expect(states, contains(true));
      expect(states.last, isFalse);
    });

    test('Status landet im Error, wenn das Senden fehlschlägt (leere Nachricht)', () async {
      final notifier = container.read(chatSendControllerProvider(groupId).notifier);

      await notifier.send('   ');

      expect(container.read(chatSendControllerProvider(groupId)).hasError, isTrue);
    });

    test('mehrfaches schnelles Antippen erzeugt nur eine gesendete Nachricht', () async {
      final notifier = container.read(chatSendControllerProvider(groupId).notifier);

      final first = notifier.send('Doppelt?');
      final second = notifier.send('Doppelt?');
      await Future.wait([first, second]);

      final messages = await container.read(chatRepositoryProvider).watchLatestMessages(groupId).first;
      expect(messages, hasLength(1));
    });
  });
}
