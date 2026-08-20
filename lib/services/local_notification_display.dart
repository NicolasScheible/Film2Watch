import 'package:flutter_local_notifications/flutter_local_notifications.dart';

const _androidChannel = AndroidNotificationChannel(
  'film2watch_default',
  'Film2Watch',
  description: 'Freundschaftsanfragen, Gruppeneinladungen, Matches und Chat-Nachrichten.',
  importance: Importance.high,
);

/// Dünne Abstraktion über `flutter_local_notifications` - reine
/// Anzeige-Schicht für Vordergrund-Notifications (kein zweites Push-System,
/// das eigentliche Versenden passiert ausschließlich über FCM/Cloud
/// Functions). Erlaubt es, [PushService] in Tests mit einem Fake zu prüfen,
/// ohne echte Plattform-Channels zu benötigen.
abstract class LocalNotificationDisplay {
  Future<void> initialize({required void Function(String? payload) onTap});
  Future<void> show({required int id, String? title, String? body, String? payload});
}

class FlutterLocalNotificationDisplay implements LocalNotificationDisplay {
  FlutterLocalNotificationDisplay(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;

  @override
  Future<void> initialize({required void Function(String? payload) onTap}) async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    await _plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (response) => onTap(response.payload),
    );
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_androidChannel);
  }

  @override
  Future<void> show({required int id, String? title, String? body, String? payload}) {
    return _plugin.show(
      id,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannel.id,
          _androidChannel.name,
          channelDescription: _androidChannel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: payload,
    );
  }
}
