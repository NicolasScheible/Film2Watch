import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repositories/device_repository.dart';
import '../services/local_notification_display.dart';
import '../services/push_messaging_client.dart';
import '../services/push_service.dart';
import 'auth_provider.dart';

final firebaseMessagingProvider = Provider<FirebaseMessaging>((ref) {
  return FirebaseMessaging.instance;
});

final pushMessagingClientProvider = Provider<PushMessagingClient>((ref) {
  return FirebaseMessagingClient(ref.watch(firebaseMessagingProvider));
});

final localNotificationsPluginProvider = Provider<FlutterLocalNotificationsPlugin>((ref) {
  return FlutterLocalNotificationsPlugin();
});

final localNotificationDisplayProvider = Provider<LocalNotificationDisplay>((ref) {
  return FlutterLocalNotificationDisplay(ref.watch(localNotificationsPluginProvider));
});

final deviceRepositoryProvider = Provider<DeviceRepository>((ref) {
  return DeviceRepository(ref.watch(firestoreProvider));
});

final pushServiceProvider = Provider<PushService>((ref) {
  return PushService(
    ref.watch(deviceRepositoryProvider),
    ref.watch(pushMessagingClientProvider),
    ref.watch(localNotificationDisplayProvider),
    platform: Platform.isIOS ? 'ios' : 'android',
  );
});

/// Initialisiert Push-Notifications genau einmal pro eingeloggtem User -
/// `FutureProvider.family` cached pro `uid`, ein erneutes `watch` mit
/// derselben uid (z. B. bei jedem Rebuild von `AppGate`) löst keine erneute
/// Permission-Anfrage/Registrierung aus.
final pushInitializationProvider = FutureProvider.family<void, String>((ref, uid) {
  return ref.watch(pushServiceProvider).initializeForUser(uid);
});
