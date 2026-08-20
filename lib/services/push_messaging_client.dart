import 'package:firebase_messaging/firebase_messaging.dart';

/// Dünne Abstraktion über die tatsächlich von [PushService] benötigten
/// FCM-Funktionen - inklusive der beiden statischen Streams `onMessage`/
/// `onMessageOpenedApp`, die sich sonst nicht durch Konstruktor-Injection
/// ersetzen ließen. Es gibt kein offizielles `firebase_messaging_mocks`-
/// Paket (anders als für Auth/Storage in diesem Projekt); diese Abstraktion
/// erlaubt es, [PushService] trotzdem mit einem vollständig kontrollierbaren
/// Fake zu testen, ohne echte Firebase-Plattform-Channels zu benötigen -
/// analog zu `TmdbService`, das über `http.Client`/`MockClient` getestet wird.
abstract class PushMessagingClient {
  Future<NotificationSettings> requestPermission();
  Future<String?> getToken();
  Stream<String> get onTokenRefresh;
  Stream<RemoteMessage> get onMessage;
  Stream<RemoteMessage> get onMessageOpenedApp;
  Future<RemoteMessage?> getInitialMessage();
}

/// Produktive Implementierung auf Basis der echten [FirebaseMessaging]-Instanz.
class FirebaseMessagingClient implements PushMessagingClient {
  FirebaseMessagingClient(this._messaging);

  final FirebaseMessaging _messaging;

  @override
  Future<NotificationSettings> requestPermission() {
    return _messaging.requestPermission(alert: true, badge: true, sound: true);
  }

  @override
  Future<String?> getToken() => _messaging.getToken();

  @override
  Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;

  @override
  Stream<RemoteMessage> get onMessage => FirebaseMessaging.onMessage;

  @override
  Stream<RemoteMessage> get onMessageOpenedApp => FirebaseMessaging.onMessageOpenedApp;

  @override
  Future<RemoteMessage?> getInitialMessage() => _messaging.getInitialMessage();
}
