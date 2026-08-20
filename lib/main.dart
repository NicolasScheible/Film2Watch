import 'package:firebase_core/firebase_core.dart' show Firebase;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'firebase_options.dart';
import 'services/firebase_service.dart';

/// Läuft in einem eigenen Hintergrund-Isolate ohne Zugriff auf den
/// App-/Widget-Zustand - Firebase muss dort separat initialisiert werden.
/// Für Notification-Payloads übernimmt das Betriebssystem die Anzeige im
/// Hintergrund/Terminated-Zustand automatisch; hier ist bewusst keine
/// zusätzliche Logik nötig (kein Firestore-Zugriff, keine zusätzliche
/// lokale Notification - das würde die native Anzeige duplizieren).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FirebaseService.initialize();
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  runApp(const ProviderScope(child: Film2WatchApp()));
}
