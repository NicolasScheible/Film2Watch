# Film2Watch

„Das Tinder für Filme mit Freunden." Freunde entscheiden gemeinsam per Swipe, welchen Film sie schauen.

## Projektstatus

Aktueller Schritt: **Gruppen-System**. Profil-, Freundes- und Profilbild-System aus Schritt 3/3.1 unverändert, jetzt inkl. echter Gruppen mit Mitgliedern, Rollen, Einladungen und Gruppenbild.

Noch **nicht** implementiert (folgt in separaten, kontrollierten Schritten):
TMDB-/Film-API, Swipe-Algorithmus, Match-Algorithmus, Gruppenchat, Push-Benachrichtigungen, Werbung, Premium.

## Tech-Stack

- **Frontend:** Flutter 3.47.0 (stable), Dart 3.13.0
- **State Management:** Riverpod
- **Backend:** Firebase (Projekt `film2watch-3385c`)
  - Firebase Core – initialisiert
  - Firebase Authentication – **produktiv**: E-Mail/Passwort (Login, Registrierung, Passwort-Reset). Google- und Apple-Sign-In sind echt implementiert, benötigen aber noch externe Konfiguration (siehe „Offene externe Konfiguration" unten)
  - Cloud Firestore – **produktiv**: User-Profile, öffentliche Profile, Freundschaften, Gruppen, Gruppenmitglieder, Gruppeneinladungen (siehe „Datenmodell" unten)
  - Firebase Cloud Messaging – als Dependency eingerichtet, noch keine Push-Logik
  - Firebase Storage – **produktiv**: Profilbild- und Gruppenbild-Upload/-Löschen
- **Plattformen:** Android (`com.film2watch`), iOS (`film2watch`)

## Projektstruktur

```
lib/
  main.dart          Einstiegspunkt, Firebase-Initialisierung
  app.dart            MaterialApp, Theme
  firebase_options.dart  Firebase-Konfiguration (aus google-services.json /
                          GoogleService-Info.plist übernommen)
  screens/
    swipe/ chat/                       Noch leere Platzhalter-Bereiche
    profile/                          Profil, Profil bearbeiten, Freund hinzufügen,
                                       Freundesanfragen
    groups/                           Gruppenliste, Gruppe erstellen/bearbeiten/Detail,
                                       Freund einladen, Gruppeneinladungen
    auth/                             Login, Registrierung, Profil-Vervollständigung
    app_shell.dart      Bottom-Navigation der fünf Hauptbereiche
    app_gate.dart        Routing zwischen Auth-Bereich und Haupt-App anhand Auth-State
  components/
    auth/                Wiederverwendbare Auth-UI (Textfeld, Buttons)
    friends/              Avatar, Listenzeile (auch für Gruppenmitglieder/-liste genutzt)
  services/            Auth-, Friend-, Group- und Storage-Service (orchestrieren Repositories)
  repositories/        Firebase-Auth- und Firestore-Zugriffsschicht
  models/               User-, PublicProfile-, FriendRequest-, Group-, GroupMember-,
                         GroupInvitation-Modelle
  providers/            Riverpod-Provider (Auth-/Freundes-/Gruppen-/Profilbild-State,
                         Formular-Controller)
  theme/                Dark-Theme, Farben
  utils/                 Validierung, Fehlerübersetzung
firestore.rules         Security Rules für alle Firestore-Collections
firestore.indexes.json  Collection-Group-Index für „meine Gruppen"
storage.rules           Security Rules für Firebase Storage (Profil-/Gruppenbilder)
firestore-tests/        Node-basierte Security-Rules-Tests gegen den echten Firestore-/Storage-Emulator
```

Architektur-Fluss: **Screens → Providers → Repositories/Services**

## Authentication

- **E-Mail/Passwort:** vollständig produktiv über `FirebaseAuth` (Registrierung, Login, `sendPasswordResetEmail`)
- **Auth-State:** `authStateChanges()` steuert reaktiv, ob der Auth-Bereich oder die Haupt-App angezeigt wird (`lib/screens/app_gate.dart`)
- **User-Dokument:** wird bei Registrierung/Erstlogin einmalig in `users/{uid}` angelegt (nie überschrieben), inkl. eindeutigem Freundescode (`FILM-XXXX`, atomare Eindeutigkeitsprüfung über `friend_codes/{code}`)
- **Namensergänzung:** Falls nach Google-/Apple-Login kein Name vorliegt, wird der Nutzer aktiv danach gefragt (keine generierten Namen)

## Datenmodell (Profil & Freunde)

| Collection | Zweck | Zugriff |
|---|---|---|
| `users/{uid}` | Privates Profil (Name, E-Mail, Freundescode, ...) | nur Owner |
| `public_profiles/{uid}` | Für andere sichtbare Teilmenge (Name, Bild, Freundescode) | `get` für jeden authentifizierten User, kein `list` (keine Enumeration möglich) |
| `friend_codes/{code}` | Eindeutigkeits-Lookup code → uid | `get` für jeden authentifizierten User |
| `friend_requests/{fromUid}_{toUid}` | Offene Freundschaftsanfrage | nur Absender/Empfänger |
| `friendships/{sortierte uidA}_{uidB}` | Bestätigte Freundschaft, ein Dokument pro Paar | nur die beiden Beteiligten |

**Warum ein Dokument pro Freundschaftspaar statt zwei Einträgen** (`users/A/friends/B` +
`users/B/friends/A`)? Damit ist eine Freundschaft strukturell immer symmetrisch – es kann nie
passieren, dass A mit B befreundet ist, B aber nicht mit A, weil es nur ein einziges Dokument
gibt. Das Annehmen einer Anfrage ist ein atomarer Batch (Freundschaft anlegen + Anfrage(n)
löschen in einem Schritt).

**Warum `public_profiles` getrennt von `users`?** `users/{uid}` ist bewusst nur für den Owner
lesbar (E-Mail etc.). Damit andere User trotzdem per Freundescode suchen bzw. Namen/Bild von
Freunden anzeigen können, existiert eine schlanke, öffentliche Teilmenge in einer eigenen
Collection – ohne dafür das private Profil öffnen zu müssen.

## Datenmodell (Gruppen)

| Collection | Zweck | Zugriff |
|---|---|---|
| `groups/{groupId}` | Gruppen-Metadaten (`name, photo_url, created_by, created_at, updated_at`) | nur Mitglieder lesen, nur Admin ändert/löscht |
| `groups/{groupId}/members/{uid}` | Mitgliedschaft + Rolle (`admin`\|`member`) | Doc-ID = uid, verhindert doppelte Mitgliedschaft |
| `group_invitations/{groupId}_{inviteeUid}` | Offene Gruppeneinladung | nur Admin des Gruppe darf einladen, nur an echte Freunde |

**„Meine Gruppen"** wird über eine Collection-Group-Query auf `members` (`where uid ==
meineUid`) gelöst statt über ein redundantes `member_uids`-Array auf dem Gruppendokument, das
bei jedem Join/Leave synchron gehalten werden müsste. Dafür ist ein Index nötig
(`firestore.indexes.json`, siehe „Offene externe Konfiguration").

**Admin-Struktur beim Verlassen:** Ein Admin kann eine Gruppe mit weiteren Mitgliedern nicht
einfach verlassen – er muss zuerst per „Admin übertragen" ein anderes Mitglied zum Admin machen
(App-/Service-Ebene, `GroupService.leaveGroup`). Ist der Admin das letzte verbliebene Mitglied,
wird die Gruppe stattdessen komplett gelöscht statt verwaist zurückzubleiben.

**Bekannte technische Grenze bei Gruppenbildern:** Firebase Storage Security Rules können keine
Firestore-Daten lesen. „Nur der Admin von Gruppe X darf das Bild ändern" lässt sich damit auf
reiner Storage-Ebene nicht durchsetzen (das bräuchte Firebase Auth Custom Claims + eine Cloud
Function, die bei Rollenänderungen synchronisiert – neue Infrastruktur, nicht Teil dieses
Schritts). `storage.rules` erlaubt daher wie beim Profilbild jedem authentifizierten Nutzer
Schreibzugriff auf `group_images/{groupId}/...`; die eigentliche Admin-Prüfung erfolgt in
`GroupService` (App-Ebene) sowie dort, wo es technisch geht: `groups/{groupId}.photo_url` ist in
Firestore weiterhin nur vom Admin änderbar, ein unautorisierter Storage-Upload würde also nie als
tatsächliches Gruppenbild in der App erscheinen.

## Profilbild

- **Auswahl:** Kamera oder Galerie über `image_picker`; Komprimierung/Verkleinerung bereits beim
  Auswählen (`maxWidth`/`maxHeight: 1024`, `imageQuality: 85`, JPEG) – kein zusätzliches
  Kompressions-Paket nötig.
- **Validierung:** Datei-Existenz, unterstütztes Format, maximale Größe (5 MB, serverseitig in
  `storage.rules` gespiegelt) vor jedem Upload.
- **Speicherort:** `profile_images/{uid}/profile.jpg` – fester Pfad, ein neues Bild überschreibt
  automatisch das alte (keine Sammlung verwaister Dateien).
- **Nach Upload:** `users/{uid}.profile_picture` und `public_profiles/{uid}.profile_picture`
  werden gemeinsam aktualisiert (analog zum Namen); `friend_code`/`email`/`created_at` bleiben
  unangetastet.
- **Entfernen:** löscht die Storage-Datei und setzt `profile_picture` zurück; der
  Initialen-Avatar ist ausschließlich die Leer-Darstellung für „kein Profilbild vorhanden".

## Firebase-Konfiguration

Die Konfigurationsdateien sind Teil des Repositories, da sie öffentliche
Client-Identifikatoren enthalten (wie bei jeder Flutter/Firebase-App üblich):

- `android/app/google-services.json`
- `ios/Runner/GoogleService-Info.plist`

Geheime Schlüssel (z. B. TMDB-API-Key) werden **nicht** im Quellcode
hinterlegt, sondern über ein separates Secret-Management eingebunden,
sobald die TMDB-Integration umgesetzt wird.

## Offene externe Konfiguration (nicht im Repository lösbar)

1. **Firestore Security Rules deployen** – `firestore.rules` (Repo-Root) muss über die
   Firebase Console (Firestore → Regeln → Inhalt einfügen) oder `firebase deploy --only firestore:rules`
   veröffentlicht werden. Die aktuelle Fassung wurde gegen den echten Firestore-Emulator
   getestet (siehe `firestore-tests/`).
2. **Google Sign-In:** In Google Cloud/Firebase Console fehlt aktuell jeder OAuth-Client für
   dieses Projekt (`oauth_client: []` in `google-services.json`, kein `CLIENT_ID` in
   `GoogleService-Info.plist`). Erforderlich: Android-OAuth-Client (SHA-1-Zertifikat-Fingerprint
   in Firebase hinterlegen) und iOS-OAuth-Client sowie ein Web-Client (für `serverClientId`)
   über Firebase Authentication → Sign-in-Methode → Google aktivieren.
3. **Apple Sign-In:** Im Apple Developer Account muss die Capability „Sign in with Apple" für
   die App-ID `film2watch` aktiviert werden; zusätzlich muss der Apple-Provider in
   Firebase Authentication → Sign-in-Methode aktiviert werden. Die iOS-Entitlements
   (`ios/Runner/Runner.entitlements`) sind bereits im Repository vorbereitet.
4. **Storage Security Rules deployen** – `storage.rules` (Repo-Root) muss über die Firebase
   Console (Storage → Regeln → Inhalt einfügen) oder `firebase deploy --only storage` veröffentlicht
   werden. Ohne deployte Regeln nutzt euer Projekt die Firebase-Standardregeln, die je nach
   Erstellungszeitpunkt des Buckets entweder alles sperren oder unsicher offen sein können – bitte
   nach dem Deployment einmal in der Console verifizieren.
5. **Firestore-Index deployen** – `firestore.indexes.json` (Collection-Group-Index auf
   `members.uid`, nötig für die „Meine Gruppen"-Liste) muss über `firebase deploy --only
   firestore:indexes` veröffentlicht werden, oder Firestore bietet beim ersten Aufruf der Query in
   der Produktion einen direkten Konsolen-Link zum Anlegen an.

Bis diese Schritte durchgeführt sind, zeigen Google-/Apple-Login in der App einen echten,
verständlichen Fehler statt eines funktionierenden Logins (kein Mock).

## Security Rules testen

`firestore.rules` und `storage.rules` werden mit echten Tests gegen die lokalen Firebase-
Emulatoren verifiziert (unterstützen – anders als reine Flutter-Fakes – `exists()`, `resource`
und Custom Functions). Details und Ausführung: [`firestore-tests/README.md`](firestore-tests/README.md).

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
