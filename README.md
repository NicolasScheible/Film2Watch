# Film2Watch

„Das Tinder für Filme mit Freunden." Freunde entscheiden gemeinsam per Swipe, welchen Film sie schauen.

## Projektstatus

Aktueller Schritt: **Projekt-Grundsetup** (Flutter-Projekt, Firebase-Anbindung, Architektur, Navigation, Dark Theme).

Noch **nicht** implementiert (folgt in separaten, kontrollierten Schritten):
TMDB-/Film-API, Swipe-Algorithmus, Match-Algorithmus, Chat-Funktionalität, Login-Flows (E-Mail/Google/Apple), Gruppenlogik, Push-Benachrichtigungen, Werbung, Premium.

## Tech-Stack

- **Frontend:** Flutter 3.47.0 (stable), Dart 3.13.0
- **State Management:** Riverpod
- **Backend:** Firebase (Projekt `film2watch-3385c`)
  - Firebase Core – initialisiert
  - Cloud Firestore – als Dependency eingerichtet, noch keine Datenmodelle/Zugriffe
  - Firebase Authentication – als Dependency eingerichtet, noch keine Login-Flows
  - Firebase Cloud Messaging – als Dependency eingerichtet, noch keine Push-Logik
- **Plattformen:** Android (`com.film2watch`), iOS (`film2watch`)

## Projektstruktur

```
lib/
  main.dart          Einstiegspunkt, Firebase-Initialisierung
  app.dart            MaterialApp, Theme
  firebase_options.dart  Firebase-Konfiguration (aus google-services.json /
                          GoogleService-Info.plist übernommen)
  screens/
    swipe/ matches/ groups/ chat/ profile/   Die fünf Hauptbereiche
    auth/                                     reserviert für Login-Flows
    app_shell.dart      Bottom-Navigation der fünf Hauptbereiche
  components/          wiederverwendbare Widgets (noch leer)
  services/            Firebase-Initialisierung u.a. technische Anbindungen
  repositories/        Datenzugriffsschicht auf Firestore (noch leer)
  models/               Datenmodelle (noch leer)
  providers/            Riverpod-Provider (App-State)
  theme/                Dark-Theme, Farben
  utils/                 Hilfsfunktionen (noch leer)
```

Architektur-Fluss: **Screens → Providers → Repositories → Services**

## Firebase-Konfiguration

Die Konfigurationsdateien sind Teil des Repositories, da sie öffentliche
Client-Identifikatoren enthalten (wie bei jeder Flutter/Firebase-App üblich):

- `android/app/google-services.json`
- `ios/Runner/GoogleService-Info.plist`

Geheime Schlüssel (z. B. TMDB-API-Key) werden **nicht** im Quellcode
hinterlegt, sondern über ein separates Secret-Management eingebunden,
sobald die TMDB-Integration umgesetzt wird.

## Entwicklung

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

### Bekannte Einschränkungen der aktuellen Entwicklungsumgebung

Diese Session lief in einer Linux-Container-Umgebung ohne Android SDK und
ohne Xcode/macOS. Dadurch konnte geprüft werden:

- `flutter analyze` ✅
- `flutter test` ✅
- Struktur/Syntax der Android-Gradle-Konfiguration ✅ (manuell geprüft)
- Struktur des iOS-Xcode-Projekts ✅ (manuell geprüft)

Nicht möglich in dieser Umgebung (erfordert echte SDKs):

- `flutter build apk` / Gradle-Sync (kein Android SDK vorhanden;
  zusätzlich blockiert die Netzwerk-Policy dieser Sandbox den Zugriff auf
  `dl.google.com`, das Gradle für Android- und Firebase-Abhängigkeiten benötigt)
- `flutter build ios` / Pod- bzw. SPM-Install (kein Xcode/macOS vorhanden)

Vor dem ersten echten Geräte-/Simulator-Test sollte das Projekt auf einem
Rechner mit vollständigem Android-SDK bzw. Xcode geöffnet und gebaut werden.
