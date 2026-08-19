import 'package:firebase_core/firebase_core.dart';

import '../firebase_options.dart';

/// Initialisiert die Verbindung zum Firebase-Projekt `film2watch-3385c`.
abstract final class FirebaseService {
  static Future<void> initialize() {
    return Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
}
