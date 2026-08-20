# Film2Watch

„Das Tinder für Filme mit Freunden." Freunde entscheiden gemeinsam per Swipe, welchen Film sie schauen.

## Projektstatus

Aktueller Schritt: **Push-Notifications**. Profil-, Freundes-, Profilbild-, Gruppen-, TMDB-, Swipe-, Match- und Chat-System aus Schritt 3/3.1/4/5/6/7/8 unverändert, jetzt inkl. echter Push-Notifications über Firebase Cloud Messaging für Freundschaftsanfragen, Gruppeneinladungen, Matches und Chat-Nachrichten.

Noch **nicht** implementiert (folgt in separaten, kontrollierten Schritten):
Filmabend-/Terminplanung, Werbung, Premium.

## Tech-Stack

- **Frontend:** Flutter 3.47.0 (stable), Dart 3.13.0
- **State Management:** Riverpod
- **Backend:** Firebase (Projekt `film2watch-3385c`)
  - Firebase Core – initialisiert
  - Firebase Authentication – **produktiv**: E-Mail/Passwort (Login, Registrierung, Passwort-Reset). Google- und Apple-Sign-In sind echt implementiert, benötigen aber noch externe Konfiguration (siehe „Offene externe Konfiguration" unten)
  - Cloud Firestore – **produktiv**: User-Profile, öffentliche Profile, Freundschaften, Gruppen, Gruppenmitglieder, Gruppeneinladungen, Gruppen-Swipes, Gruppen-Matches, Gruppenchat-Nachrichten, FCM-Geräte-Tokens (siehe „Datenmodell" unten)
  - Cloud Functions – **produktiv**: `onSwipeWritten` erkennt Matches serverseitig (siehe „Match-Funktion"); vier weitere Functions versenden Push-Notifications (siehe „Push-Notifications" unten)
  - Firebase Cloud Messaging – **produktiv**: Freundschaftsanfragen, Gruppeneinladungen, Matches, Chat-Nachrichten (siehe „Push-Notifications" unten)
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
    chat/                              Echte Chat-Übersicht: listet die Gruppen des Nutzers,
                                       Tippen öffnet den echten Gruppenchat (kein
                                       gruppenübergreifender Chat)
    profile/                          Profil, Profil bearbeiten, Freund hinzufügen,
                                       Freundesanfragen
    groups/                           Gruppenliste, Gruppe erstellen/bearbeiten/Detail (inkl.
                                       Match-Liste), Freund einladen, Gruppeneinladungen, echte
                                       Gruppen-Swipe-Session (`group_swipe_screen.dart`) und
                                       echter Gruppenchat (`group_chat_screen.dart`)
    movies/                            TMDB Test/Browse-Seite, Filmdetails (dient auch als
                                       Match-Detailansicht, siehe „Match-Funktion")
    auth/                             Login, Registrierung, Profil-Vervollständigung
    app_shell.dart      Bottom-Navigation der fünf Hauptbereiche
    app_gate.dart        Routing zwischen Auth-Bereich und Haupt-App anhand Auth-State
  components/
    auth/                Wiederverwendbare Auth-UI (Textfeld, Buttons)
    friends/              Avatar, Listenzeile (auch für Gruppenmitglieder/-liste genutzt)
    movies/                Filmkarte, zieh-/wischbare Swipe-Karte (`swipe_card.dart`),
                           Match-Karte (`match_card.dart`)
    chat/                  Chat-Bubble (`message_bubble.dart`)
  services/            Auth-, Friend-, Group-, Storage-, Tmdb-, TmdbImage-, Swipe- und Chat-Service,
                         PushService + PushMessagingClient/LocalNotificationDisplay (FCM-Anbindung)
  repositories/        Firebase- und TMDB-Zugriffsschicht (inkl. Swipe-, Match-, Chat- und
                         Device-Repository)
  models/               User-, PublicProfile-, FriendRequest-, Group-, GroupMember-,
                         GroupInvitation-, Movie-, MoviePage-, WatchProviderOption-,
                         MovieSwipe-, MovieMatch-, ChatMessage-, DeviceToken-Modelle
  providers/            Riverpod-Provider (Auth-/Freundes-/Gruppen-/Profilbild-/TMDB-/Swipe-/
                         Match-/Chat-/Notification-State, Formular-Controller)
  navigation/            Globaler Navigator-Key + Deep-Link-Navigation für Notification-Taps
  theme/                Dark-Theme, Farben
  utils/                 Validierung, Fehlerübersetzung, TMDB-Konfiguration, Notification-Payload
firestore.rules         Security Rules für alle Firestore-Collections
firestore.indexes.json  Collection-Group-Index für „meine Gruppen"
storage.rules           Security Rules für Firebase Storage (Profil-/Gruppenbilder)
firestore-tests/        Node-basierte Security-Rules-Tests gegen den echten Firestore-/Storage-Emulator
functions/               Cloud Functions (Match-Erkennung + Push-Notification-Versand)
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

## Datenmodell (Matches)

| Collection | Zweck | Zugriff |
|---|---|---|
| `groups/{groupId}/matches/{movieId}` | Ein Film, den **alle** aktuellen Mitglieder geliked haben (`movie_id, member_count, like_count, created_at`) | lesbar für alle Mitglieder der Gruppe, **kein** Client-Schreibzugriff (`allow write: if false`) |

Auch hier: kein vollständiges TMDB-JSON in Firestore, nur die Match-Referenz (`movie_id` +
Metadaten). Die Dokument-ID ist deterministisch die `movieId` – ein Film kann in einer Gruppe
strukturell nie doppelt als Match entstehen.

**Warum kategorisch kein Client-Schreibzugriff?** Ob ein Film ein Match ist, hängt von *allen*
aktuellen Swipes *aller* aktuellen Mitglieder ab. Firestore Security Rules können das nicht
sicher selbst prüfen – die Rules-Sprache kennt keine Aggregation/Schleife über eine beliebig
lange Collection (kein `COUNT`, kein `WHERE`, kein `for`), nur `get()`/`exists()` auf einzelne,
namentlich bekannte Pfade. Ein Client könnte also grundsätzlich ein manipuliertes Match-Dokument
einreichen, ohne dass eine reine Rule das zuverlässig erkennen könnte. Diese technische Grenze
wurde bewusst nicht mit einer unsicheren/getrickten Rule umgangen, sondern mit einer echten
serverseitigen Autorität gelöst – siehe „Match-Funktion" unten.

## Match-Funktion

- **Serverseitige Erkennung (Cloud Function):** `functions/index.js` registriert einen
  Firestore-Trigger `onSwipeWritten` auf `groups/{groupId}/swipes/{swipeId}`. Bei jedem
  Anlegen/Ändern eines Swipes lädt `functions/matchEngine.js` (mit Admin-Rechten, umgeht die
  Security Rules) die aktuelle Mitgliederliste der Gruppe sowie alle Swipes zum betroffenen Film
  und prüft **pro Mitglieds-UID einzeln**, ob eine Like-Entscheidung vorliegt – bewusst keine
  reine Like-*Anzahl* gegen die Mitgliederzahl, damit ein Swipe eines Users, der die Gruppe
  zwischenzeitlich verlassen hat, nie fälschlich mitzählt. Haben alle aktuellen Mitglieder
  geliked, wird das Match-Dokument einmalig und atomar (Firestore-Transaktion mit
  Existenz-Prüfung) angelegt – race-condition-sicher, kein doppeltes Dokument, selbst wenn zwei
  Mitglieder nahezu gleichzeitig liken.
- **Client darf niemals selbst matchen:** Die Firestore Rules verbieten jeden Schreibzugriff auf
  `matches` kategorisch (`allow write: if false`) – nur die Cloud Function (Admin-SDK) kann
  Match-Dokumente erzeugen. Es gibt bewusst kein `match_service.dart` mit einer
  Schreib-/Erzeugungs-Methode, da eine clientseitige „Match erzeugen"-Funktion ohnehin wirkungslos
  wäre.
- **Endgültiges Ergebnis:** Ändert ein Mitglied seine Bewertung, nachdem ein Match bereits
  entstanden ist (Like → Dislike), oder verlässt es die Gruppe, bleibt das bestehende
  Match-Dokument unverändert bestehen – ein Match ist ein dauerhafter Beleg, kein flüchtiger
  Zustand, der bei einer Meinungsänderung wieder verschwindet (analog zu einem „Match" in
  vergleichbaren Swipe-Apps). Solange ein Film hingegen noch **nicht** gematcht ist, wird jede
  Bewertungsänderung korrekt in die laufende Auswertung einbezogen (Like → Dislike verhindert das
  Zustandekommen, Dislike → Like kann es auslösen).
- **Echtzeit-Anzeige:** `groupMatchesProvider(groupId)` (Riverpod `StreamProvider`) hält die
  Match-Liste einer Gruppe live aktuell (`MatchRepository.watchMatches`, Firestore-Snapshot-
  Stream) – kein manuelles Neuladen nötig.
- **Match-Liste & -Details:** Ein echter „Matches"-Bereich in `GroupDetailScreen` zeigt die
  Match-Karten (`MatchCard`, Poster im Vordergrund, Titel, Bewertung – echte TMDB-Daten über das
  bestehende `movieDetailsProvider`, keine zweite API-Anbindung). Ohne Matches ein ehrlicher Empty
  State „Noch kein gemeinsamer Film." – keine Fake-Karten. Antippen einer Match-Karte öffnet die
  bestehende `MovieDetailScreen` (Poster, Backdrop, Titel, Beschreibung, Genres, Bewertung,
  Laufzeit, Erscheinungsjahr, Streaming-Anbieter) – bewusst keine zweite, redundante
  „Match-Detail"-Seite.
- **Reaktion beim Swipen:** Entsteht während einer laufenden Swipe-Session ein neues Match, zeigt
  `GroupSwipeScreen` einen „Match! 🍿"-Dialog mit Poster (reagiert auf `groupMatchesProvider`,
  nicht auf eine eigene, redundante Zähllogik in der UI). Die Match-*Erkennung* selbst bleibt
  vollständig serverseitig – `SwipeCard` und die Swipe-Business-Logik aus Schritt 6 wurden dafür
  nicht verändert.
- **Nicht Teil dieses Schritts:** Gruppenchat, Filmabend-/Terminplanung, Push-Benachrichtigungen.

## Datenmodell (Chat)

| Collection | Zweck | Zugriff |
|---|---|---|
| `groups/{groupId}/messages/{messageId}` | Eine Chat-Nachricht (`sender_uid, text, created_at`) | lesbar/anlegbar für Mitglieder der Gruppe, kein Update/Delete |

Firestore-Auto-ID pro Nachricht. Bewusst **keine** `sender_name`/`sender_profile_picture`-Kopie im
Dokument: beide lassen sich zuverlässig über das bestehende `public_profiles/{uid}` nachschlagen
(`publicProfileProvider`) – eine Kopie hier wäre unnötige Redundanz und könnte veralten, wenn sich
Name/Bild später ändern. `created_at` wird ausschließlich serverseitig über
`FieldValue.serverTimestamp()` gesetzt – die lokale Gerätezeit ist keine vertrauenswürdige Quelle;
die Security Rule erzwingt das (`created_at == request.time`), ein client-gesetzter Zeitstempel
wird abgelehnt.

**Maximale Nachrichtenlänge:** 2000 Zeichen (`chatMaxMessageLength` in `lib/services/chat_service.dart`,
identisch in `firestore.rules` gespiegelt). Ohne konkrete Vorgabe aus einer übergeordneten
Spezifikation ein bewusst gewählter, dokumentierter Standardwert – groß genug für normale
Chat-Nachrichten, klein genug, um kein Missbrauchsvektor für übergroße Dokumente zu sein.

**Nachrichten sind in dieser ersten Version unveränderlich** (`allow update, delete: if false`):
kein Bearbeiten/Löschen durch normale Mitglieder. Eine spätere Erweiterung (z. B. eigene
Nachrichten löschen) ist ein eigener, bewusst nicht in diesem Schritt vorweggenommener
Entwicklungsschritt.

## Chat-Funktion

- **Architektur:** `ChatRepository` (Firestore-Zugriff auf `groups/{groupId}/messages`) →
  `ChatService` (validiert Text und prüft die Mitgliedschaft, bevor überhaupt geschrieben wird –
  die Firestore Rules erzwingen dieselben Prüfungen zusätzlich serverseitig) →
  `ChatSendController` (Senden auslösen) + `chatMessagesProvider`/`ChatHistoryController`
  (Nachrichtenliste + Pagination) → UI. Kein direkter Firestore-Zugriff aus Widgets.
- **Echtzeit:** `chatMessagesProvider(groupId)` ist ein Firestore-Snapshot-Stream der letzten 30
  Nachrichten (älteste zuerst) – neue Nachrichten erscheinen ohne manuellen Reload bei allen
  Gruppenmitgliedern gleichzeitig.
- **Pagination:** Beim Öffnen wird bewusst nicht die komplette Historie geladen, sondern nur die
  letzten 30 Nachrichten (`ChatRepository.watchLatestMessages`, `limitToLast`). Ältere Nachrichten
  lassen sich über einen Button („Ältere Nachrichten laden") gezielt nachladen
  (`ChatHistoryController.loadOlder`, einmaliger `get()` vor dem ältesten bekannten Zeitstempel) –
  kein unbegrenzter Stream über die gesamte Historie.
- **Bedienung:** Textfeld + Senden-Button unten, Senden auch über die Tastatur-Aktion (Enter/Send).
  Leere oder nur aus Leerzeichen bestehende Nachrichten werden clientseitig gar nicht erst
  abgeschickt; das Eingabefeld wird direkt nach dem Absenden geleert. Der Senden-Button ist
  während eines laufenden Sendevorgangs deaktiviert (`state.isLoading` im `ChatSendController`) –
  kein Doppel-Senden bei schnellem Mehrfach-Tap. Schlägt das Senden fehl, verschwindet die
  eingegebene Nachricht nicht kommentarlos – ein verständlicher Fehler wird angezeigt.
- **UI:** Eigene Nachrichten rechts (Akzentfarbe), fremde Nachrichten links mit echtem Avatar/Namen
  aus `public_profiles`. Jede Nachricht zeigt Text und Uhrzeit. Ehrlicher Empty State „Noch keine
  Nachrichten." – keine Demo-Nachricht. Bestehendes Dark Theme, keine neue Farbpalette.
- **Gruppenintegration:** `GroupDetailScreen` hat einen echten „Chat"-Button neben „Filme swipen",
  der `GroupChatScreen(groupId)` öffnet. Der globale **Chat**-Tab der Bottom Navigation (vorher ein
  Platzhalter) zeigt jetzt die Gruppen des Nutzers – Tippen öffnet den jeweiligen echten Gruppenchat
  (kein gruppenübergreifender Chat, kein Fake-Inhalt).
- **Sicherheit:** Manipulierte `groupId` ermöglicht keinen Zugriff auf fremde Chats – das wird
  unabhängig von der UI durch `firestore.rules` erzwungen (`isGroupMember(groupId)` für read/create,
  `sender_uid == request.auth.uid`, `update`/`delete` kategorisch `false`).
- **Nicht Teil dieses Schritts:** Match-Systemnachrichten im Chat, Push-Benachrichtigungen,
  Filmabend-/Terminplanung, RSVP, Watch Party. Keine neue Cloud Function – normale
  Chat-Nachrichten kommen ohne serverseitige Logik aus, Firestore Rules reichen aus.

## Datenmodell (FCM-Geräte-Tokens)

| Collection | Zweck | Zugriff |
|---|---|---|
| `users/{uid}/devices/{token}` | Ein FCM-Gerät des Users (`token, platform, created_at, updated_at`) | ausschließlich der Owner (read/create/update/delete) |

Ein User kann mehrere Geräte haben – deshalb kein einzelnes `users/{uid}.fcm_token`-Feld, sondern
eine eigene Subcollection. Dokument-ID ist deterministisch der Token selbst: ein Gerät kann so
strukturell nie doppelt registriert werden, und ein Token-Refresh ist einfach „neues Dokument für
den neuen Token anlegen, altes Dokument entfernen" statt eines fehleranfälligen In-Place-Updates
des Token-Werts. `created_at`/`updated_at` sind serverseitige Timestamps
(`FieldValue.serverTimestamp()`), von der Security Rule über `request.time` erzwungen.

## Push-Notifications

- **Architektur:** Client initialisiert FCM nur für sich selbst – Permission anfragen, eigenes
  Gerät registrieren, eigenes Token aktualisieren, lokale Anzeige im Vordergrund konfigurieren.
  Das tatsächliche Versenden an *andere* Nutzer passiert ausschließlich serverseitig über vier
  Cloud Functions (`functions/notify*.js`), niemals aus dem Flutter-Client heraus.
- **Client-Flow:** `PushService` (orchestriert FCM: Permission, Token-Registrierung/-Refresh,
  Tap-Handling) → `DeviceRepository` (Firestore-Zugriff auf `users/{uid}/devices`). FCM selbst wird
  über zwei dünne Abstraktionen angebunden – `PushMessagingClient` (kapselt `FirebaseMessaging`
  inkl. der beiden statischen Streams `onMessage`/`onMessageOpenedApp`) und
  `LocalNotificationDisplay` (kapselt `flutter_local_notifications`) – da es kein offizielles
  Mock-Paket für `firebase_messaging` gibt; das macht `PushService` trotzdem vollständig mit Fakes
  testbar, analog zu `TmdbService`/`http.Client`.
- **Vordergrund-Anzeige:** `flutter_local_notifications` ist eine reine Anzeige-Schicht, kein
  zweites Push-System. Es wird bewusst kein `setForegroundNotificationPresentationOptions(alert:
  true)` gesetzt – dadurch zeigt iOS Vordergrund-Notifications nicht selbst an, die Anzeige läuft
  ausschließlich über den eigenen `onMessage`-Listener. Es gibt also nie zwei Anzeige-Pfade
  gleichzeitig.
- **Ereignisse (alle serverseitig, Firestore-Trigger auf bereits bestehenden Pfaden):**
  - `friend_requests/{requestId}` (`onCreate`) → Empfänger (`toUid`) bekommt „Neue
    Freundschaftsanfrage" + Name des Absenders. Der Absender bekommt nichts.
  - `group_invitations/{invitationId}` (`onCreate`) → die eingeladene Person (`inviteeUid`)
    bekommt „Neue Gruppeneinladung" + Gruppenname. Sonst niemand.
  - `groups/{groupId}/matches/{matchId}` (`onCreate`) → alle aktuellen Mitglieder der Gruppe
    bekommen „Neuer Match!" + Gruppenname. Es gibt keinen einzelnen „Ersteller", der ausgeschlossen
    werden müsste – ein Match ist ein gemeinsames, serverseitig ermitteltes Ergebnis; der
    Duplikat-Schutz (siehe unten) stellt sicher, dass dafür in jedem Fall nur eine
    Notification-Runde verschickt wird. **Bewusst der Gruppenname statt des Filmtitels:**
    Filmdaten kommen ausschließlich von TMDB (clientseitig) – Cloud Functions haben keinen
    TMDB-Zugriff und sollen auch keinen bekommen, um TMDB nicht zu duplizieren. Der Filmtitel
    erscheint nach dem Antippen ganz normal in der bestehenden Match-/Filmdetail-Anzeige.
  - `groups/{groupId}/messages/{messageId}` (`onCreate`) → alle Mitglieder außer dem Absender
    bekommen „{Name} in {Gruppe}" + eine gekürzte Vorschau (max. 80 Zeichen) der Nachricht. Der
    Absender bekommt nie eine eigene Notification.
- **Duplikat-Schutz:** Cloud Functions garantieren nur „at-least-once"-Zustellung – derselbe
  Trigger kann in seltenen Fällen erneut ausgeführt werden. `claimNotification()`
  (`functions/notifications.js`) beansprucht das Senderecht atomar über eine Firestore-Transaktion
  (prüft/setzt ein `notified_at`-Feld auf dem jeweiligen Quelldokument) – nur der erste
  erfolgreiche Aufruf sendet tatsächlich, jeder weitere bricht sauber ab. Kein naives „ein Trigger
  = garantiert eine Notification".
- **Token-Cleanup:** `sendToUsers()` inspiziert die FCM-Antwort pro Token; meldet FCM
  `registration-token-not-registered`/`invalid-registration-token`, wird das betroffene
  Device-Dokument gelöscht – kein endloses erneutes Zustellen an tote Tokens.
- **Fehlerbehandlung:** Ein fehlgeschlagener Notification-Versand wirft nie in den aufrufenden
  Trigger hinein und beeinflusst nie den ursprünglichen Firestore-Hauptvorgang (Anfrage/Einladung/
  Match/Nachricht) – der ist zu diesem Zeitpunkt bereits abgeschlossen.
- **Payload/Privacy:** `data`-Payload enthält nur `type` und ggf. `group_id` – keine vollständigen
  Nachrichten, keine privaten Profildaten, keine internen Firebase-IDs über das Nötige hinaus. Die
  sichtbare Chat-Vorschau ist bewusst gekürzt. Keine Device-Tokens oder Secrets werden geloggt.
- **Deep Links:** `navigateForNotification()` (`lib/navigation/notification_navigator.dart`)
  nutzt einen globalen `navigatorKey` auf dem bestehenden `MaterialApp` – Freundschaftsanfrage →
  `FriendRequestsScreen`, Gruppeneinladung → `GroupInvitationsScreen`, Match → `GroupDetailScreen`
  (zeigt die Match-Liste), Chat → `GroupChatScreen`. Derselbe Code-Pfad wird sowohl vom
  FCM-Tap-Handler (Hintergrund/Terminated) als auch vom Tap auf die lokale
  Vordergrund-Notification aufgerufen – keine doppelte Navigations-Logik, keine neue parallele
  Navigations-Architektur.
- **App-Zustände:** Foreground über `onMessage` + lokale Anzeige; Background/Terminated zeigt das
  Betriebssystem die Notification anhand des `notification`-Blocks automatisch an, ein Tap wird
  über `onMessageOpenedApp` (App im Hintergrund) bzw. `getInitialMessage()` (App war beendet)
  verarbeitet.
- **Logout:** Meldet zuerst das eigene Gerät ab (`PushService.unregisterCurrentDevice`), bevor
  tatsächlich ausgeloggt wird – danach ist der User nicht mehr authentifiziert, die Security Rules
  würden das Entfernen des eigenen Device-Dokuments dann nicht mehr erlauben. Betrifft
  ausschließlich das eigene Gerät, nie fremde.
- **Keine Notification-Einstellungsseite:** In diesem Schritt nicht vorgesehen (keine
  übergeordnete Spezifikation dafür) – keine künstliche Preference-Architektur erfunden.
- **Nicht Teil dieses Schritts:** Internes Notification-Center/Inbox in der App (FCM-Push ist
  nicht dasselbe wie ein internes Notification-Center).

### Android

- `POST_NOTIFICATIONS`-Permission im Manifest ergänzt (ab Android 13/API 33 zur Laufzeit
  erforderlich, damit `requestPermission()` eine echte System-Abfrage auslösen kann).
- Keine weiteren Manifest-Änderungen nötig – `firebase_messaging`/`flutter_local_notifications`
  registrieren ihre Services/Receiver automatisch über das Gradle-Plugin.

### iOS / APNs

**Bereits vorhanden:**
- `firebase_messaging`-Dependency, Firebase-Projekt `film2watch-3385c` (unverändert, keine neue
  Firebase-App registriert), Bundle-ID `film2watch` (unverändert).
- `UIBackgroundModes` mit `remote-notification` in `Info.plist` ergänzt (zuverlässige
  Hintergrund-Zustellung).
- `aps-environment: development` in `Runner.entitlements` ergänzt (Debug-/TestFlight-Builds; vor
  einem App-Store-Release muss dieser Wert auf `production` geändert werden).

**Fehlt – echte externe Konfiguration, hier nicht herstellbar (kein Vortäuschen):**
- Die **„Push Notifications"-Capability** ist im Xcode-Projekt selbst noch nicht über die
  Apple-Developer-Provisioning-Profile aktiviert (das entitlement-Vorbereiten im Repo ersetzt das
  nicht – dafür muss jemand mit Zugriff auf das Apple Developer Portal die Capability für die
  App-ID `film2watch` aktivieren und ein passendes Provisioning-Profile ziehen).
- Ein **APNs-Auth-Key** (`.p8`, Apple Developer → Certificates, Identifiers & Profiles → Keys) muss
  erzeugt und in der Firebase Console (Projekteinstellungen → Cloud Messaging → Apple-App-
  Konfiguration) hinterlegt werden. Ohne diesen Key kann Firebase keine Pushes an iOS-Geräte
  zustellen – kein Zertifikat/Key wurde erfunden oder committet.

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
7. **Cloud Functions deployen** – `functions/` (serverseitige Match-Erkennung + Push-Notification-
   Versand) muss über `firebase deploy --only functions` veröffentlicht werden. Das Firebase-
   Projekt muss dafür auf den **Blaze-Tarif (Pay-as-you-go)** umgestellt sein – Cloud Functions
   laufen nicht auf dem kostenlosen Spark-Tarif. Ohne deployte Functions entstehen echte Swipes/
   Nachrichten/Anfragen weiterhin normal, aber es werden **keine** Match-Dokumente und **keine**
   Push-Notifications erzeugt (kein Fake-Fallback).
8. **APNs für iOS** (Schritt 9, siehe „Push-Notifications" → „iOS / APNs" oben für den vollen
   Status): „Push Notifications"-Capability im Apple Developer Portal für die App-ID `film2watch`
   aktivieren + ein passendes Provisioning-Profile ziehen, sowie einen APNs-Auth-Key erzeugen und
   in der Firebase Console (Cloud Messaging → Apple-App-Konfiguration) hinterlegen. Ohne diese
   beiden Schritte erhalten iOS-Geräte keine Push-Notifications; Android ist davon unabhängig und
   funktioniert bereits vollständig über die Firebase-Projektkonfiguration.

Bis diese Schritte durchgeführt sind, zeigen Google-/Apple-Login in der App einen echten,
verständlichen Fehler statt eines funktionierenden Logins (kein Mock).

## Security Rules testen

`firestore.rules` und `storage.rules` werden mit echten Tests gegen die lokalen Firebase-
Emulatoren verifiziert (unterstützen – anders als reine Flutter-Fakes – `exists()`, `resource`
und Custom Functions). Details und Ausführung: [`firestore-tests/README.md`](firestore-tests/README.md).

Die Match-*Erkennungslogik* (`functions/matchEngine.js`) wird separat als echter End-to-End-Test
gegen den Firebase Functions Emulator + Firestore Emulator getestet (`functions/test/`, `npm test`
in `functions/`) – Swipes werden real in Firestore geschrieben, der echte Cloud-Function-Trigger
läuft mit, und es wird auf das entstehende (oder ausbleibende) Match-Dokument gewartet.

Die Push-Notification-*Logik* (`functions/notifications.js`, `functions/notify*.js`) wird gegen
den echten Firestore-Emulator getestet, aber mit einem injizierten Fake-Messaging-Client statt
echtem FCM-Versand: es gibt keinen „Firebase Cloud Messaging Emulator", und ohne echte
Gerätetokens/Google-Cloud-Credentials in einer CI-/Sandbox-Umgebung wäre ein echter Versand
ohnehin nicht sinnvoll testbar. Geprüft werden die tatsächliche Empfänger-Ermittlung, der
Ausschluss des Absenders, der Duplikat-Schutz und das Entfernen ungültiger Tokens – also exakt die
Logik, die bei einem echten Versand zählt.

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
