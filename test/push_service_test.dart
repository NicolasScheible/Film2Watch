import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:film2watch/repositories/device_repository.dart';
import 'package:film2watch/services/push_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/push_fakes.dart';

void main() {
  // navigateForNotification() greift auf GlobalKey.currentState zu, was
  // intern WidgetsBinding.instance voraussetzt - auch in reinen
  // test()-Fällen ohne echten Widget-Baum (siehe "8." unten).
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PushService', () {
    late FakeFirebaseFirestore firestore;
    late DeviceRepository deviceRepository;
    late FakePushMessagingClient messagingClient;
    late FakeLocalNotificationDisplay localNotifications;
    late PushService pushService;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      deviceRepository = DeviceRepository(firestore);
      messagingClient = FakePushMessagingClient();
      localNotifications = FakeLocalNotificationDisplay();
      pushService = PushService(
        deviceRepository,
        messagingClient,
        localNotifications,
        platform: 'android',
      );
    });

    tearDown(() => messagingClient.dispose());

    test('1. FCM-Initialisierung fordert Permission an und registriert das Gerät', () async {
      await pushService.initializeForUser('alice');

      expect(messagingClient.requestPermissionCallCount, 1);
      expect(messagingClient.getTokenCallCount, 1);
    });

    test('2. bei abgelehnter Permission wird kein Gerät registriert', () async {
      messagingClient.authorizationStatus = AuthorizationStatus.denied;

      await pushService.initializeForUser('alice');

      final doc = await firestore
          .collection('users')
          .doc('alice')
          .collection('devices')
          .doc('initial-test-token')
          .get();
      expect(doc.exists, isFalse);
    });

    test('3. Device-Token wird in Firestore registriert', () async {
      await pushService.initializeForUser('alice');

      final doc = await firestore
          .collection('users')
          .doc('alice')
          .collection('devices')
          .doc('initial-test-token')
          .get();
      expect(doc.exists, isTrue);
      expect(doc.data()!['platform'], 'android');
      expect(pushService.registeredToken, 'initial-test-token');
    });

    test('4. Token-Refresh registriert den neuen Token und entfernt den alten', () async {
      await pushService.initializeForUser('alice');

      messagingClient.emitTokenRefresh('refreshed-token');
      await Future.delayed(Duration.zero);

      final devices = firestore.collection('users').doc('alice').collection('devices');
      expect((await devices.doc('refreshed-token').get()).exists, isTrue);
      expect((await devices.doc('initial-test-token').get()).exists, isFalse);
      expect(pushService.registeredToken, 'refreshed-token');
    });

    test('5. Logout entfernt nur das eigene, aktuell registrierte Gerät', () async {
      await pushService.initializeForUser('alice');
      // Ein fremdes Gerät eines anderen Users darf davon nie betroffen sein.
      await deviceRepository.registerDevice(uid: 'bob', token: 'bobs-token', platform: 'ios');

      await pushService.unregisterCurrentDevice('alice');

      final aliceDoc = await firestore
          .collection('users')
          .doc('alice')
          .collection('devices')
          .doc('initial-test-token')
          .get();
      final bobDoc = await firestore
          .collection('users')
          .doc('bob')
          .collection('devices')
          .doc('bobs-token')
          .get();
      expect(aliceDoc.exists, isFalse);
      expect(bobDoc.exists, isTrue);
      expect(pushService.registeredToken, isNull);
    });

    test('7. Vordergrund-Notification wird genau einmal lokal angezeigt', () async {
      await pushService.initializeForUser('alice');

      messagingClient.emitForegroundMessage(
        const RemoteMessage(
          data: {'type': 'chat_message', 'group_id': 'g1'},
          notification: RemoteNotification(title: 'Neue Nachricht', body: 'Hallo!'),
        ),
      );
      await Future.delayed(Duration.zero);

      expect(localNotifications.shown, hasLength(1));
      expect(localNotifications.shown.single.title, 'Neue Nachricht');
      expect(localNotifications.shown.single.body, 'Hallo!');
    });

    test('Vordergrund-Nachricht ohne notification-Block wird nicht angezeigt', () async {
      await pushService.initializeForUser('alice');

      messagingClient.emitForegroundMessage(
        const RemoteMessage(data: {'type': 'chat_message', 'group_id': 'g1'}),
      );
      await Future.delayed(Duration.zero);

      expect(localNotifications.shown, isEmpty);
    });

    test('8. Tap auf eine Hintergrund-Notification wird verarbeitet, ohne abzustürzen', () async {
      await pushService.initializeForUser('alice');

      // Simuliert onMessageOpenedApp (App war im Hintergrund, User hat auf
      // die System-Notification getippt).
      messagingClient.emitOpenedAppMessage(
        const RemoteMessage(data: {'type': 'group_invitation', 'group_id': 'g1'}),
      );
      await Future.delayed(Duration.zero);
      // Die konkrete Navigation wird separat in notification_navigator_test.dart
      // geprüft (dort mit echtem Navigator/BuildContext) - hier wird nur
      // verifiziert, dass der Tap-Pfad ohne registrierten Navigator (wie im
      // Test-Setup) sauber ignoriert wird statt abzustürzen.
    });

    test('getInitialMessage (Terminated-Start durch Notification-Tap) wird verarbeitet', () async {
      messagingClient.initialMessage = const RemoteMessage(
        data: {'type': 'match', 'group_id': 'g1'},
      );

      await pushService.initializeForUser('alice');
      // Kein Absturz - siehe Kommentar oben.
    });
  });
}
