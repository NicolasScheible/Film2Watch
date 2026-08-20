import 'dart:async';

import 'package:film2watch/services/local_notification_display.dart';
import 'package:film2watch/services/push_messaging_client.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

/// Test-Double für [PushMessagingClient] - es gibt kein offizielles
/// `firebase_messaging_mocks`-Paket, daher wird hier die von
/// `PushService` benötigte Teilmenge der FCM-API vollständig
/// kontrollierbar nachgebildet (kein echter Plattform-Channel nötig).
class FakePushMessagingClient implements PushMessagingClient {
  FakePushMessagingClient({
    this.token = 'initial-test-token',
    this.authorizationStatus = AuthorizationStatus.authorized,
    this.initialMessage,
  });

  String? token;
  AuthorizationStatus authorizationStatus;
  RemoteMessage? initialMessage;

  int requestPermissionCallCount = 0;
  int getTokenCallCount = 0;

  final _tokenRefreshController = StreamController<String>.broadcast();
  final _onMessageController = StreamController<RemoteMessage>.broadcast();
  final _onMessageOpenedAppController = StreamController<RemoteMessage>.broadcast();

  @override
  Future<NotificationSettings> requestPermission() async {
    requestPermissionCallCount++;
    return NotificationSettings(
      alert: AppleNotificationSetting.enabled,
      announcement: AppleNotificationSetting.notSupported,
      authorizationStatus: authorizationStatus,
      badge: AppleNotificationSetting.enabled,
      carPlay: AppleNotificationSetting.notSupported,
      lockScreen: AppleNotificationSetting.enabled,
      notificationCenter: AppleNotificationSetting.enabled,
      showPreviews: AppleShowPreviewSetting.always,
      timeSensitive: AppleNotificationSetting.notSupported,
      criticalAlert: AppleNotificationSetting.notSupported,
      sound: AppleNotificationSetting.enabled,
      providesAppNotificationSettings: AppleNotificationSetting.notSupported,
    );
  }

  @override
  Future<String?> getToken() async {
    getTokenCallCount++;
    return token;
  }

  @override
  Stream<String> get onTokenRefresh => _tokenRefreshController.stream;

  @override
  Stream<RemoteMessage> get onMessage => _onMessageController.stream;

  @override
  Stream<RemoteMessage> get onMessageOpenedApp => _onMessageOpenedAppController.stream;

  @override
  Future<RemoteMessage?> getInitialMessage() async => initialMessage;

  void emitTokenRefresh(String newToken) => _tokenRefreshController.add(newToken);
  void emitForegroundMessage(RemoteMessage message) => _onMessageController.add(message);
  void emitOpenedAppMessage(RemoteMessage message) => _onMessageOpenedAppController.add(message);

  Future<void> dispose() async {
    await _tokenRefreshController.close();
    await _onMessageController.close();
    await _onMessageOpenedAppController.close();
  }
}

class ShownNotification {
  const ShownNotification({required this.id, this.title, this.body, this.payload});
  final int id;
  final String? title;
  final String? body;
  final String? payload;
}

/// Test-Double für [LocalNotificationDisplay] - zeichnet auf, was
/// "angezeigt" wurde, statt echte Plattform-Channels zu benötigen.
class FakeLocalNotificationDisplay implements LocalNotificationDisplay {
  final List<ShownNotification> shown = [];
  void Function(String? payload)? _onTap;

  @override
  Future<void> initialize({required void Function(String? payload) onTap}) async {
    _onTap = onTap;
  }

  @override
  Future<void> show({required int id, String? title, String? body, String? payload}) async {
    shown.add(ShownNotification(id: id, title: title, body: body, payload: payload));
  }

  void simulateTap(String? payload) => _onTap?.call(payload);
}
