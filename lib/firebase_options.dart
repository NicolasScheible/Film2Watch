import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;

/// Firebase-Konfiguration für das Projekt `film2watch-3385c`.
///
/// Werte wurden manuell aus den bereitgestellten Konfigurationsdateien
/// übernommen (android/app/google-services.json, ios/Runner/GoogleService-Info.plist),
/// nicht mit der FlutterFire CLI generiert. Bei Änderungen an den Firebase-Apps
/// müssen diese Werte entsprechend aktualisiert werden.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'DefaultFirebaseOptions wurden nicht für Web konfiguriert.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions sind für diese Plattform nicht konfiguriert: '
          '$defaultTargetPlatform. Film2Watch unterstützt aktuell nur Android und iOS.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBRQ_ChUHia6CpIxukLZx_6Fmk7-Mfyf3o',
    appId: '1:204739675477:android:c894dc9582e4e747ecdbdc',
    messagingSenderId: '204739675477',
    projectId: 'film2watch-3385c',
    storageBucket: 'film2watch-3385c.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDg_eJ9dPU6F-MbP9XSxDLz8JuHz80Q3uo',
    appId: '1:204739675477:ios:e9effee1e11877e5ecdbdc',
    messagingSenderId: '204739675477',
    projectId: 'film2watch-3385c',
    storageBucket: 'film2watch-3385c.firebasestorage.app',
    iosBundleId: 'film2watch',
  );
}
