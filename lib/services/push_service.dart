import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';

import '../navigation/notification_navigator.dart';
import '../repositories/device_repository.dart';
import '../utils/notification_payload.dart';
import 'local_notification_display.dart';
import 'push_messaging_client.dart';

/// Orchestriert Firebase Cloud Messaging: Permission, Geräte-Registrierung,
/// Token-Refresh sowie die lokale Anzeige im Vordergrund über
/// [LocalNotificationDisplay] (reine Anzeige-Schicht, kein zweites
/// Push-System; das tatsächliche Versenden an andere Nutzer passiert
/// ausschließlich serverseitig über Cloud Functions, siehe `functions/`).
///
/// Bewusst kein `setForegroundNotificationPresentationOptions(alert: true)`:
/// damit zeigt iOS Vordergrund-Notifications nicht automatisch selbst an -
/// die Anzeige läuft ausschließlich über den eigenen `onMessage`-Listener
/// unten, es gibt also nie zwei Anzeige-Pfade gleichzeitig.
class PushService {
  PushService(
    this._deviceRepository,
    this._messaging,
    this._localNotifications, {
    required this.platform,
  });

  final DeviceRepository _deviceRepository;
  final PushMessagingClient _messaging;
  final LocalNotificationDisplay _localNotifications;
  final String platform;

  String? _registeredToken;
  StreamSubscription<String>? _refreshSubscription;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _openedAppSubscription;
  bool _displayInitialized = false;

  /// Nur für Tests: der zuletzt für den aktuellen User registrierte Token.
  String? get registeredToken => _registeredToken;

  Future<void> _ensureDisplayInitialized() async {
    if (_displayInitialized) return;
    _displayInitialized = true;
    await _localNotifications.initialize(onTap: _handleLocalNotificationTap);
  }

  /// Fordert die Notification-Permission an, registriert das aktuelle Gerät
  /// und richtet Token-Refresh sowie Tap-Handling ein. Wird einmalig pro
  /// eingeloggtem User aufgerufen (siehe `pushInitializationProvider`).
  /// Schlägt die Permission-Anfrage fehl oder wird sie abgelehnt, bricht
  /// nichts anderes in der App ab - Push ist ein optionales Zusatzfeature.
  Future<void> initializeForUser(String uid) async {
    await _ensureDisplayInitialized();

    final settings = await _messaging.requestPermission();
    if (settings.authorizationStatus == AuthorizationStatus.denied) return;

    final token = await _messaging.getToken();
    if (token != null) {
      _registeredToken = token;
      await _deviceRepository.registerDevice(uid: uid, token: token, platform: platform);
    }

    await _refreshSubscription?.cancel();
    _refreshSubscription = _messaging.onTokenRefresh.listen((newToken) async {
      final oldToken = _registeredToken;
      _registeredToken = newToken;
      await _deviceRepository.registerDevice(uid: uid, token: newToken, platform: platform);
      if (oldToken != null && oldToken != newToken) {
        // Best-effort: schlägt das Entfernen des alten Tokens fehl, räumt
        // die serverseitige Cloud Function ungültige Tokens ohnehin auf.
        unawaited(_deviceRepository.removeDevice(uid: uid, token: oldToken).catchError((_) {}));
      }
    });

    await _foregroundSubscription?.cancel();
    _foregroundSubscription = _messaging.onMessage.listen(_showForegroundNotification);

    await _openedAppSubscription?.cancel();
    _openedAppSubscription = _messaging.onMessageOpenedApp.listen(_handleRemoteMessageTap);

    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) _handleRemoteMessageTap(initialMessage);
  }

  /// Meldet das aktuelle Gerät ab (Logout) - betrifft ausschließlich das
  /// eigene, aktuell registrierte Gerät, niemals fremde Geräte.
  Future<void> unregisterCurrentDevice(String uid) async {
    final token = _registeredToken;
    if (token == null) return;
    await _deviceRepository.removeDevice(uid: uid, token: token);
    await _refreshSubscription?.cancel();
    _refreshSubscription = null;
    _registeredToken = null;
  }

  void _showForegroundNotification(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;

    _localNotifications.show(
      id: notification.hashCode,
      title: notification.title,
      body: notification.body,
      payload: jsonEncode(message.data),
    );
  }

  void _handleRemoteMessageTap(RemoteMessage message) {
    navigateForNotification(NotificationPayload.fromData(message.data));
  }

  void _handleLocalNotificationTap(String? payloadJson) {
    if (payloadJson == null) return;
    final decoded = jsonDecode(payloadJson);
    if (decoded is! Map<String, dynamic>) return;
    navigateForNotification(NotificationPayload.fromData(decoded));
  }
}
