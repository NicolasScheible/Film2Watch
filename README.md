# Film2Watch

„Das Tinder für Filme mit Freunden." Freunde entscheiden gemeinsam per Swipe, welchen Film sie schauen.

## Projektstatus

Aktueller Schritt: **Gruppen-Film-Swipe**. Profil-, Freundes-, Profilbild-, Gruppen- und TMDB-System aus Schritt 3/3.1/4/5 unverändert, jetzt inkl. echter Swipe-Funktion: Gruppenmitglieder bewerten TMDB-Filme per Wisch-Geste oder Button mit Like/Dislike, die Entscheidung wird dauerhaft in Firestore gespeichert.

Noch **nicht** implementiert (folgt in separaten, kontrollierten Schritten):
Match-Erkennung/-Anzeige (auch wenn mehrere Mitglieder denselben Film liken, wird das in diesem Schritt bewusst noch nicht ausgewertet), Gruppenchat, Push-Benachrichtigungen, Werbung, Premium.

## Tech-Stack

- **Frontend:** Flutter 3.47.0 (stable), Dart 3.13.0
- **State Management:** Riverpod
- **Backend:** Firebase (Projekt `film2watch-3385c`)
  - Firebase Core – initialisiert
  - Firebase Authentication – **produktiv**: E-Mail/Passwort (Login, Registrierung, Passwort-Reset). Google- und Apple-Sign-In sind echt implementiert, benötigen aber noch externe Konfiguration (siehe „Offene externe Konfiguration" unten)
  - Cloud Firestore – **produktiv**: User-Profile, öffentliche Profile, Freundschaften, Gruppen, Gruppenmitglieder, Gruppeneinladungen, Gruppen-Swipes (siehe „Datenmodell" unten)
  - Firebase Cloud Messaging – als Dependency eingerichtet, noch keine Push-Logik
  - Firebase Storage – **produktiv**: Profilbild- und Gruppenbild-Upload/-Löschen
- **Filmdaten:** TMDB API (`https://api.themoviedb.org/3`) – **produktiv**: Discover, Suche, Details, Watch-Provider (siehe „TMDB-Integration" unten). Kein eigener Filmdaten-Cache in Firestore, TMDB bleibt alleinige Quelle.
- **Plattformen:** Android (`com.film2watch`), iOS (`film2watch`)

## Projektstruktur

```
lib/
  main.dart          Einstiegspunkt, Firebase-Initialisierung
  app.dart            MaterialApp, Theme
  firebase_options.dart  Firebase-Konfiguration (aus google-services.json /
                          GoogleService-Info.plist übernommen)
  screens/
    swipe/                             Platzhalter + Link zur TMDB-Testseite (Einstieg in die
                                       echte Swipe-Session erfolgt über eine Gruppe, siehe unten)
    chat/                              Noch leerer Platzhalter-Bereich
    profile/                          Profil, Profil bearbeiten, Freund hinzufügen,
                                       Freundesanfragen
    groups/                           Gruppenliste, Gruppe erstellen/bearbeiten/Detail,
                                       Freund einladen, Gruppeneinladungen, echte Gruppen-
                                       Swipe-Session (`group_swipe_screen.dart`)
    movies/                            TMDB Test/Browse-Seite, Filmdetails (Verifikation der
                                       TMDB-Integration, keine Match-UI)
    auth/                             Login, Registrierung, Profil-Vervollständigung
    app_shell.dart      Bottom-Navigation der fünf Hauptbereiche
    app_gate.dart        Routing zwischen Auth-Bereich und Haupt-App anhand Auth-State
  components/
    auth/                Wiederverwendbare Auth-UI (Textfeld, Buttons)
    friends/              Avatar, Listenzeile (auch für Gruppenmitglieder/-liste genutzt)
    movies/                Filmkarte (Poster + Titel + Bewertung), zieh-/wischbare Swipe-Karte
                           (`swipe_card.dart`)
  services/            Auth-, Friend-, Group-, Storage-, Tmdb-, TmdbImage- und Swipe-Service
  repositories/        Firebase- und TMDB-Zugriffsschicht (inkl. Swipe-Repository)
  models/               User-, PublicProfile-, FriendRequest-, Group-, GroupMember-,
                         GroupInvitation-, Movie-, MoviePage-, WatchProviderOption-,
                         MovieSwipe-Modelle
  providers/            Riverpod-Provider (Auth-/Freundes-/Gruppen-/Profilbild-/TMDB-/Swipe-
                         State, Formular-Controller)
  theme/                Dark-Theme, Farben
  utils/                 Validierung, Fehlerübersetzung, TMDB-Konfiguration
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

## Datenmodell (Swipes)

| Collection | Zweck | Zugriff |
|---|---|---|
| `groups/{groupId}/swipes/{uid}_{movieId}` | Like/Dislike-Entscheidung eines Mitglieds zu einem Film (`uid, movie_id, decision, created_at, updated_at`) | lesbar für alle Mitglieder der Gruppe, schreibbar nur für den eigenen Swipe, kein Löschen |

Es wird **keine** vollständige TMDB-JSON-Antwort in Firestore gespeichert – nur die
Entscheidung selbst (`movie_id` + `like`/`dislike`). TMDB bleibt für alle Filmdaten (Titel,
Poster, Genres, ...) die alleinige Quelle.

**Deterministische Dokument-ID `{uid}_{movieId}`:** Ein erneutes Bewerten desselben Films durch
denselben User in derselben Gruppe aktualisiert die bestehende Entscheidung (`update`), statt ein
zweites Dokument anzulegen – strukturell unmöglich, doppelte oder widersprüchliche Einträge zu
erzeugen. Die Security Rules trennen `create` (Erstanlage, prüft `request.auth.uid ==
request.resource.data.uid` und das ID-Muster) sauber von `update` (nur der Owner, `uid`/`movie_id`/
`created_at` bleiben unveränderlich) und verbieten `delete` vollständig – das ist für diesen Schritt
nicht vorgesehen.

**Lesbarkeit für alle Mitglieder statt nur den Owner:** Eine spätere Match-Auswertung (eigener,
noch nicht implementierter Schritt) muss vergleichen können, wer welchen Film geliked hat – dafür
müssen Mitglieder auch die Swipes anderer Mitglieder derselben Gruppe lesen dürfen. Schreiben bleibt
trotzdem strikt auf den eigenen Swipe beschränkt.

## Swipe-Funktion

- **Architektur:** `SwipeRepository` (Firestore-Zugriff auf `groups/{groupId}/swipes`) →
  `SwipeService` (prüft die Mitgliedschaft, bevor überhaupt geschrieben wird – die Firestore
  Rules erzwingen dieselbe Prüfung zusätzlich serverseitig) → `SwipeActionController`
  (Like/Dislike auslösen) + `SwipeQueueController` (Warteschlange unbewerteter Filme) → UI. Kein
  direkter Firestore-/TMDB-Zugriff aus Widgets.
- **Filmauswahl:** echte TMDB-Discover-Seiten (`MovieRepository.discoverMovies`, siehe
  „TMDB-Integration"); Filme, die der aktuelle User in dieser Gruppe bereits bewertet hat, werden
  clientseitig herausgefiltert (`SwipeRepository.getSwipedMovieIds`). Weitere TMDB-Seiten werden
  automatisch nachgeladen, sobald die Warteschlange knapp wird, begrenzt auf maximal 5
  Seitenabrufe pro Auffüll-Vorgang, um bei ungünstiger Datenlage keine unkontrollierte Schleife
  auszulösen.
- **Bedienung:** Wischen nach rechts = Like, nach links = Dislike (mit sichtbarer
  Richtungsanzeige während des Ziehens); die Like-/Dislike-Buttons lösen exakt denselben Code-Pfad
  wie die Geste aus (`SwipeCardState.triggerLike`/`triggerDislike` über einen `GlobalKey`), keine
  doppelte Business-Logik.
- **Speichern & Fehlerbehandlung:** Die Entscheidung wird erst nach der Wisch-/Tap-Animation
  gespeichert; schlägt das Speichern fehl (kein Internet, Firestore-Fehler, ...), verschwindet die
  Karte **nicht** kommentarlos – ein Fehler wird angezeigt und der User kann es erneut versuchen.
  Mehrfaches schnelles Antippen wird über den `state.isLoading`-Zustand des
  `SwipeActionController` abgefangen, es kann nie ein doppelter Swipe für denselben Tap ausgelöst
  werden.
- **Leerer Zustand:** „Keine weiteren Filme verfügbar." wird ausschließlich angezeigt, wenn TMDB
  wirklich keine weiteren Seiten mehr liefert – kein endloser Ladeindikator.
- **Nicht Teil dieses Schritts:** Match-Erkennung (auch wenn mehrere Mitglieder denselben Film
  liken), Gruppenchat, Push-Benachrichtigungen.

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

## TMDB-Integration

- **Architektur:** `TmdbService` (roher, fehlergeprüfter HTTP-Client, `package:http`) →
  `MovieRepository` (mappt JSON auf das interne `Movie`-Modell, löst Genre-IDs zu Namen auf,
  einfacher In-Memory-Cache für Genre-Liste + zuletzt geladene Filmdetails) → Riverpod-Provider/
  Controller → Screens. TMDB-Zugriffe passieren nie direkt aus Widgets.
- **Endpunkte:** Discover Movies, Search Movies, Movie Details, Genre List (intern für die
  Genre-Namen-Auflösung), Watch Providers (Streaming-Verfügbarkeit).
- **Fehlerbehandlung:** typisierte Exceptions für fehlenden API-Key, kein Internet/Timeout,
  401/403/404/429/5xx sowie ungültige Antworten – werden in der UI zu verständlichen deutschen
  Meldungen übersetzt, nie als rohe Exception angezeigt. Bei 429 (Rate Limit) erfolgt **kein**
  automatischer Retry-Loop, nur eine Meldung zum späteren erneuten Versuch.
- **Pagination:** `MovieRepository` lädt eine Seite auf Anfrage; `DiscoverMoviesController`/
  `MovieSearchController` (Riverpod) hängen weitere Seiten dedupliziert an (`mergeUniqueMovies`,
  Abgleich über `tmdbId`).
- **Caching:** Genre-Liste (ändert sich praktisch nie) und die letzten 100 abgerufenen
  Film-Details werden im `MovieRepository` im Speicher gehalten, um nicht bei jeder UI-Aktion
  denselben Film erneut zu laden. Kein Offline-System, kein Duplizieren von Filmdaten nach
  Firestore – TMDB bleibt alleinige Quelle.
- **Region/Sprache:** Standard `de-DE`/`DE`, aber per `--dart-define=TMDB_LANGUAGE=...` bzw.
  `--dart-define=TMDB_REGION=...` überschreibbar, ohne Code-Änderung – nicht hart auf Deutschland
  verdrahtet.
- **Bild-URLs:** zentral über `TmdbImageService` (Poster/Backdrop/Provider-Logo), keine manuell
  zusammengebauten URL-Strings im restlichen Code.

### TMDB API Key (Secret-Handling)

**Es ist noch kein TMDB API Key hinterlegt – dieser wird für echte TMDB-Requests benötigt.**

Der Zugang wird ausschließlich zur Build-Zeit über `--dart-define` injiziert, niemals im
Quellcode oder in einer eingecheckten `.env`-Datei:

```bash
flutter run --dart-define=TMDB_ACCESS_TOKEN=euer_tmdb_read_access_token
```

Ohne gesetzten Token zeigt die App auf der TMDB-Testseite ehrlich „TMDB API Key wird benötigt."
an, statt Requests mit einem falschen/leeren Schlüssel zu versuchen oder Daten vorzutäuschen. Der
Token ist der TMDB **„API Read Access Token"** (Bearer-Token, nicht der ältere „API Key (v3
auth)"), zu finden im TMDB-Account unter Einstellungen → API.

## TMDB Test/Browse-Seite

Im **Swipe**-Tab gibt es aktuell nur einen Platzhalter mit einem Button „TMDB Test / Browse" –
das ist bewusst keine fertige Swipe-Oberfläche, sondern eine technische Verifikationsseite mit
echten TMDB-Daten (Suche + Beliebtheits-Liste + Filmdetails inkl. Streaming-Verfügbarkeit), um die
Integration zu prüfen.

## Firebase-Konfiguration

Die Konfigurationsdateien sind Teil des Repositories, da sie öffentliche
Client-Identifikatoren enthalten (wie bei jeder Flutter/Firebase-App üblich):

- `android/app/google-services.json`
- `ios/Runner/GoogleService-Info.plist`

Geheime Schlüssel (z. B. der TMDB API Key) werden **nicht** im Quellcode
hinterlegt, sondern per `--dart-define` injiziert – siehe „TMDB-Integration" oben.

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
6. **TMDB API Read Access Token** – wird für alle echten TMDB-Requests benötigt (siehe
   „TMDB-Integration" oben). Ohne ihn zeigt die TMDB-Testseite den Hinweis „TMDB API Key wird
   benötigt.", es werden keine Fake-Daten angezeigt.

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
