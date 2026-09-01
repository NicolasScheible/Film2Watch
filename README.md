# Film2Watch

„Das Tinder für Filme mit Freunden." Freunde entscheiden gemeinsam per Swipe, welchen Film sie schauen.

## Projektstatus

Aktueller Schritt: **Cast-Anti-Boost „gleicher Hauptdarsteller" (§7/§18)**. Profil-, Freundes-,
Profilbild-, Gruppen-, TMDB-, Swipe- (inkl. Watchlist-Ansicht, Filtersystem, Trailer-Button,
Watchlist-Eintrag entfernen, vollem Boost-Algorithmus und Super Swipe), Match-, Chat-, Push-,
Onboarding- und globaler Swipe-Tab-Schritt aus den vorherigen Schritten unverändert. Der zuvor
zurückgestellte zweite Anti-Boost-Faktor aus §7 („Ein Dislike senkt den Score ähnlicher Filme
(gleiches Genre, gleicher Hauptdarsteller) leicht (–10)") ist jetzt ebenfalls umgesetzt: eine neue
TMDB-Credits-Integration (`TmdbService.movieCredits`) liefert die Top-3-Hauptdarsteller-IDs eines
Films, ein Dislike senkt darüber zusätzlich zum bestehenden Genre-Anti-Boost auch den Score
zukünftiger Kandidaten mit überschneidender Hauptbesetzung – siehe „Boost-Algorithmus" unten für die
vollständige Herleitung inkl. der mit dem Produktverantwortlichen abgestimmten
„Hauptdarsteller"-Definition.

Noch **nicht** implementiert (folgt in separaten, kontrollierten Schritten):
Boost-Bonus für Super Swipe (Master-Spezifikation nennt keinen Wert), **echte Premium-Aktivierung**
(RevenueCat/App-Store-/Play-Store-Abo - benötigt
externe Zahlungs-/Store-Konfiguration, die in dieser Umgebung nicht existiert; nur das
Datenmodell/Gating ist bereits fertig), sowie die übrigen Premium-Vorteile aus §15 (werbefrei,
erweiterte Filter, unbegrenzte Gruppen, Statistiken), Filmabend-/Terminplanung, Werbung. Ebenfalls
noch offen: eine UI/Geste, mit der ein Nutzer einen Super Swipe tatsächlich auslöst - die
Master-Spezifikation beschreibt dafür keine konkrete Interaktion (die vier bestehenden
Wisch-Richtungen sind bereits belegt).

## Tech-Stack

- **Frontend:** Flutter 3.47.0 (stable), Dart 3.13.0
- **State Management:** Riverpod
- **Backend:** Firebase (Projekt `film2watch-3385c`)
  - Firebase Core – initialisiert
  - Firebase Authentication – **produktiv**: E-Mail/Passwort (Login, Registrierung, Passwort-Reset). Google- und Apple-Sign-In sind echt implementiert, benötigen aber noch externe Konfiguration (siehe „Offene externe Konfiguration" unten)
  - Cloud Firestore – **produktiv**: User-Profile, öffentliche Profile, Freundschaften, Gruppen, Gruppenmitglieder, Gruppeneinladungen, Gruppen-Swipes, Gruppen-Matches, Gruppenchat-Nachrichten, FCM-Geräte-Tokens (siehe „Datenmodell" unten)
  - Cloud Functions – **produktiv**: `onSwipeWritten` erkennt Matches serverseitig (siehe „Match-System"); vier weitere Functions versenden Push-Notifications (siehe „Push-Notifications" unten)
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
                                       Match-Detailansicht, siehe „Match-System")
    matches/                           Gruppenübergreifender „Matches"-Tab (`matches_screen.dart`,
                                       siehe „Match-System")
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

## Onboarding

- **Ablauf:** Direkt nachdem `AppGate` feststellt, dass Name und Profil vollständig sind, aber
  `users/{uid}.onboarding_completed` noch `false` ist, zeigt es statt `AppShell` den
  `OnboardingScreen` – ein dreiteiliges Tutorial (`PageView`): (1) Rechts/Links = Like/Dislike,
  (2) Runter/Hoch = Skip/Watchlist ("Vielleicht später"), (3) Freunde per Freundescode hinzufügen.
  Genau diese beiden Themen fordert die Produktspezifikation, keine weiteren Folien wurden erfunden.
- **Nur einmal, geräteübergreifend:** Der Abschluss (Button „Los geht's" auf der letzten Folie oder
  „Überspringen" jederzeit) wird über `UserRepository.completeOnboarding` serverseitig auf
  `users/{uid}.onboarding_completed` gespeichert (kein lokaler Gerätespeicher) – `currentUserDocProvider`
  reagiert darauf reaktiv, `AppGate` schaltet automatisch zu `AppShell` weiter, ohne manuelle
  Navigation. Ein Login auf einem neuen Gerät zeigt das Tutorial deshalb nicht erneut.
- **Keine neue Security Rule nötig:** `firestore.rules` erlaubt für `users/{userId}` bereits jedes
  Feld außer `uid`/`email`/`friend_code`/`created_at` als veränderlich für den Owner selbst – exakt
  dasselbe Muster wie bei `updateName`/`updateProfilePicture`.

## Datenmodell (Profil & Freunde)

| Collection | Zweck | Zugriff |
|---|---|---|
| `users/{uid}` | Privates Profil (Name, E-Mail, Freundescode, `onboarding_completed`, ...) | nur Owner |
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
| `groups/{groupId}/swipes/{uid}_{movieId}` | Like/Dislike/Skip/Watchlist/Super-Swipe-Entscheidung eines Mitglieds zu einem Film (`uid, movie_id, decision, created_at, updated_at`, optional `genre_ids`, optional `cast_ids`) | lesbar für alle Mitglieder der Gruppe, schreibbar nur für den eigenen Swipe (`decision == 'super'` zusätzlich nur mit Premium-Status); löschbar nur für den eigenen Swipe, wenn `decision == 'watchlist'` (Watchlist-Eintrag entfernen) – Like/Dislike/Skip/Super bleiben unlöschbar |
| `user_preferences/{uid}` | Personalisierter Boost-Zustand für den Genre-/Cast-Bonus/Anti-Boost (§7/§18/§17.4): `genre_affinity`, `disliked_genres`, `top_genres`, `disliked_cast_ids`, `last_updated` | lesbar nur für den eigenen User; schreibbar für niemanden clientseitig – ausschließlich die Cloud Function `functions/userPreferences.js` (Admin-SDK) schreibt |
| `premium_status/{uid}` | Premium-Status für Super Swipe und weitere §15-Vorteile (§6/§15): `is_premium` | lesbar nur für den eigenen User; schreibbar für niemanden clientseitig – die tatsächliche Aktivierung (RevenueCat/Store-Abo, §18) ist offene externe Konfiguration, nicht Teil dieses Repositories |

Es wird **keine** vollständige TMDB-JSON-Antwort in Firestore gespeichert – nur die
Entscheidung selbst (`movie_id` + `like`/`dislike`/`skip`/`watchlist`/`super`) und, für den
Boost-Algorithmus, die TMDB-Genre-IDs (`genre_ids`) sowie die Top-3-Hauptdarsteller-IDs (`cast_ids`)
des Films zum Swipe-Zeitpunkt (jeweils nur numerische IDs, keine Namen/Bilder/vollständigen
Cast-Daten). TMDB bleibt für alle eigentlichen Filmdaten (Titel, Poster, Beschreibung, ...) die
alleinige Quelle.

**Deterministische Dokument-ID `{uid}_{movieId}`:** Ein erneutes Bewerten desselben Films durch
denselben User in derselben Gruppe aktualisiert die bestehende Entscheidung (`update`), statt ein
zweites Dokument anzulegen – strukturell unmöglich, doppelte oder widersprüchliche Einträge zu
erzeugen. Die Security Rules trennen `create` (Erstanlage, prüft `request.auth.uid ==
request.resource.data.uid` und das ID-Muster) sauber von `update` (nur der Owner, `uid`/`movie_id`/
`created_at` bleiben unveränderlich) und verbieten `delete` vollständig – das ist für diesen Schritt
nicht vorgesehen.

**Lesbarkeit für alle Mitglieder statt nur den Owner:** Die serverseitige Match-Auswertung (siehe
„Match-System" unten) muss vergleichen können, wer welchen Film geliked hat – dafür müssen
Mitglieder auch die Swipes anderer Mitglieder derselben Gruppe lesen dürfen. Schreiben bleibt
trotzdem strikt auf den eigenen Swipe beschränkt.

## Swipe-Funktion

- **Globaler Einstiegspunkt (`SwipeScreen`, Swipe-Tab der Bottom Navigation):** Zeigt die Gruppen
  des Nutzers (`myGroupsProvider`, dieselbe Datenquelle wie `GroupsScreen`/`ChatScreen`) als Liste;
  Tippen öffnet den `GroupSwipeScreen` der jeweiligen Gruppe. Kein gruppenübergreifender
  Swipe-Modus: Ein Swipe ist laut Datenmodell (§5, §17.4) immer an genau eine `group_id` gebunden,
  daher gibt es keine Aggregation mehrerer Gruppen in einem gemeinsamen Feed und keinen impliziten
  „Standard"-Gruppen-Kontext – der Nutzer wählt die Gruppe explizit. Ehrlicher Empty State „Tritt
  einer Gruppe bei, um dort Filme zu swipen.", wenn der Nutzer in keiner Gruppe ist.
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
- **Bedienung:** Wischen nach rechts = Like, nach links = Dislike, nach unten = Skip/„Vielleicht
  später", nach oben = Watchlist/„Vielleicht später" (mit sichtbarer Richtungsanzeige während des
  Ziehens, `LIKE`/`NOPE`/`SKIP`/`WATCHLIST`, die dominante Zug-Achse entscheidet zwischen
  horizontal und vertikal); die Like-/Dislike-/Skip-/Watchlist-Buttons lösen exakt denselben
  Code-Pfad wie die jeweilige Geste aus
  (`SwipeCardState.triggerLike`/`triggerDislike`/`triggerSkip`/`triggerWatchlist` über einen
  `GlobalKey`), keine doppelte Business-Logik.
- **Skip und Watchlist sind rein persönlich:** Beide „Vielleicht später"-Entscheidungen blenden den
  Film ausschließlich für den swipenden User aus der eigenen Warteschlange dieser Gruppe aus
  (`SwipeQueueController`/`SwipeRepository.getSwipedMovieIds` behandelt `like`/`dislike`/`skip`/
  `watchlist` identisch als „bereits bewertet") – andere Mitglieder sehen und bewerten denselben
  Film unverändert weiter. Beide zählen in der serverseitigen Match-Erkennung
  (`functions/matchEngine.js`, prüft ausschließlich `decision == 'like'`) nie als Like, können also
  selbst nie einen Match auslösen, und blockieren auch keinen zukünftigen Match anderer Mitglieder –
  dafür war keine Änderung an der Match-Engine nötig, die bestehende Prüfung war bereits eng genug
  gefasst.
- **Watchlist-Ansicht (`GroupDetailScreen`):** Ein „Watchlist"-Bereich zeigt jeden Film, den
  mindestens ein *aktuelles* Mitglied der Gruppe vorgemerkt hat – rein lesend über die bestehenden
  Watchlist-Swipes (`SwipeRepository.watchWatchlist`), keine neue Collection und keine zweite
  Watchlist-Datenquelle. `groupWatchlistProvider` (`swipe_provider.dart`) fasst dabei mehrere
  Mitglieder, die denselben Film vorgemerkt haben, zu einem Eintrag zusammen und filtert Einträge
  ehemaliger Mitglieder heraus – analog zur bestehenden Match-Erkennung, die ebenfalls nur aktuelle
  Mitglieder zählt. Jede Karte (`WatchlistCard`, optisch an `MatchCard` orientiert) zeigt ein Badge
  mit dem Gruppen-Abgleich: „Du hast vorgemerkt", wenn nur der aktuelle User ihn vorgemerkt hat,
  sonst „X/Y vorgemerkt" (X = Mitglieder mit Vormerkung, Y = aktuelle Gruppengröße). Die Watchlist
  ist bewusst **persönlich pro Nutzer und Gruppe**, keine gruppenübergreifende Ansicht – Antippen
  öffnet wie bei Matches die bestehende `MovieDetailScreen`.
- **Watchlist-Eintrag entfernen:** Auf der eigenen `WatchlistCard` erscheint oben rechts ein
  Entfernen-Button (nur, wenn der aktuelle User den Film tatsächlich selbst vorgemerkt hat – fremde
  Einträge zeigen keinen Button und sind nicht entfernbar). Antippen öffnet zuerst einen
  Bestätigungsdialog (`_WatchlistSection._confirmRemove` in `group_detail_screen.dart`, derselbe
  `showDialog<bool>`/`AlertDialog`-Aufbau wie beim bestehenden „Gruppe verlassen"/„Gruppe
  löschen"-Dialog, kein neues UI-Muster) – „Abbrechen" oder das Wegtippen des Dialogs lässt den
  Eintrag unverändert bestehen, nur „Entfernen" löst das eigentliche Löschen aus. Entfernen löscht
  das bestehende Swipe-Dokument `groups/{groupId}/swipes/{uid}_{movieId}` vollständig
  (`SwipeRepository.removeSwipe` → `SwipeService.removeFromWatchlist`, geprüft über
  `WatchlistRemoveController`), statt nur die `decision` zu ändern: Der Film gilt danach wieder als
  unbewertet und kann bei der nächsten Warteschlangen-Befüllung erneut in der eigenen Swipe-Queue
  auftauchen und neu bewertet werden (`SwipeRepository.getSwipedMovieIds` findet kein Dokument mehr
  dazu). Firestore Rules erlauben `delete` ausschließlich für den eigenen Swipe mit
  `decision == 'watchlist'` – ein fremder Eintrag, eine andere Gruppe oder ein Like-/Dislike-/
  Skip-Swipe bleiben serverseitig unlöschbar. Ein gelöschter Swipe fehlt in der Match-Erkennung
  (`functions/matchEngine.js`) einfach als Eintrag und zählt damit strukturell nie als Like –
  Entfernen kann also nie selbst einen Match auslösen; Likes/Dislikes/Watchlist-Einträge anderer
  Mitglieder bleiben unverändert, der Gruppen-Abgleich (`groupWatchlistProvider`) aktualisiert sich
  automatisch über den bestehenden Firestore-Stream. Während des Löschens zeigt die Karte einen
  Ladeindikator statt des Buttons (`WatchlistCard.isRemoving`, pro Karte einzeln über
  `WatchlistRemoveController.removingMovieId`, kein globaler Ladezustand für alle Karten) und
  verhindert Double-Submit; schlägt das Löschen fehl, erscheint eine ehrliche Fehlermeldung als
  Snackbar (`translateGroupError`).
- **Speichern & Fehlerbehandlung:** Die Entscheidung wird erst nach der Wisch-/Tap-Animation
  gespeichert; schlägt das Speichern fehl (kein Internet, Firestore-Fehler, ...), verschwindet die
  Karte **nicht** kommentarlos – ein Fehler wird angezeigt und der User kann es erneut versuchen.
  Mehrfaches schnelles Antippen wird über den `state.isLoading`-Zustand des
  `SwipeActionController` abgefangen, es kann nie ein doppelter Swipe für denselben Tap ausgelöst
  werden.
- **Leerer Zustand:** „Keine weiteren Filme verfügbar." wird ausschließlich angezeigt, wenn TMDB
  wirklich keine weiteren Seiten mehr liefert – kein endloser Ladeindikator.

### Filtersystem (§10)

- **Umfang:** Plattform (Einzelauswahl inkl. „Alle" im MVP – Mehrfachauswahl ist laut §15
  ausdrücklich ein Premium-Feature und nicht Teil dieses Schritts), Genre (Mehrfachauswahl,
  ODER-verknüpft), Erscheinungsjahr (Bereich „von/bis", 1900 bis aktuelles Jahr – dynamisch über
  `DateTime.now()`, nicht hartkodiert), Mindestbewertung (native TMDB-`vote_average`-Skala 0–10)
  und Filmlänge (Bereich „von/bis Minuten", 0–240). Alle konkreten Wertebereiche wurden explizit
  mit dem Product Owner abgestimmt, da die Master-Spezifikation selbst keine Zahlen nennt.
- **Architektur:** `MovieFilter` (`lib/models/movie_filter.dart`, reines Wert-Objekt, kein
  Firestore-Modell) → `TmdbService.discoverMovies`/`watchProviderList` (native TMDB-Discover-
  Parameter: `with_watch_providers`, `with_genres` mit Pipe-Syntax für ODER,
  `primary_release_date.gte`/`.lte`, `vote_average.gte`, `with_runtime.gte`/`.lte`) →
  `MovieRepository.discoverMovies(filter:)`/`getAvailableWatchProviders()`/`getGenres()` →
  `MovieFilterController` (`movie_filter_provider.dart`, session-lokaler `Notifier` pro Gruppe) →
  `SwipeQueueController` (liest den Filter per `ref.watch`, jeder Filterwechsel löst automatisch
  einen vollständigen Neuaufbau der Warteschlange aus – keine alten, unter dem vorherigen Filter
  geladenen Filme bleiben zurück) → `MovieFilterScreen` (UI). Keine zweite TMDB-Integration, keine
  neue Firestore-Collection.
- **Plattformliste:** Echte, bei TMDB für die konfigurierte Region tatsächlich verfügbare
  Streaming-Anbieter (`/watch/providers/movie`, im `MovieRepository` gecacht) – keine selbst
  erfundene Plattformliste.
- **Persistenz:** Bewusst **keine** – die Master-Spezifikation verlangt an keiner Stelle eine
  dauerhafte Speicherung der Filterauswahl. Der Filter ist eine reine Session-Einstellung
  (`Notifier`-State, kein `ref.watch`/`.family` auf Firestore) und gilt individuell pro Nutzer und
  Gruppe – ein Filterwechsel in einer Gruppe beeinflusst nie die Swipe-Session einer anderen
  Gruppe oder eines anderen Mitglieds.
- **Gruppenbezug:** Der Filter wirkt ausschließlich auf die eigene Warteschlange innerhalb der
  aktuell gewählten Gruppe (`GroupSwipeScreen`) – kein gruppenloser Swipe, keine Änderung an der
  strikten `groupId`-Bindung jedes Swipes.
- **Bereits geswipte Filme:** Bleiben mit jedem Filter weiterhin ausgeschlossen
  (`SwipeRepository.getSwipedMovieIds` unverändert, wirkt unabhängig vom aktiven Filter).
- **UI:** `MovieFilterScreen`, erreichbar über ein Filter-Icon (`Icons.tune`) in der AppBar von
  `GroupSwipeScreen` mit einem Badge für die Anzahl aktiver Filterkriterien. Änderungen werden erst
  mit „Anwenden" übernommen; Zurück-Navigation ohne „Anwenden" verwirft den Entwurf, ohne den
  aktiven Filter der Session zu verändern. „Zurücksetzen" ist deaktiviert, solange kein Filter aktiv
  ist. Bestehendes Dark Theme (`AppColors`), keine neue Farbpalette, keine Fake-Daten – Plattformen
  und Genres werden live von TMDB geladen.

### Boost-Algorithmus (§7/§18)

- **Exakte Vorgabe (§7):** ein additiver Score aus fünf Faktoren, wörtlich aus der
  Beispielrechnung übernommen: Freundes-Likes (+40), persönliche Genre-Präferenz (+30, „wer *oft*
  Horror liked"), Anti-Boost bei Dislikes (–10, „gleiches Genre, gleicher Hauptdarsteller"),
  Bewertung (Rating × 5) und eine Zufallskomponente (0–20). §18 gab dafür ausdrücklich einen
  zweistufigen Umsetzungsweg vor: zuerst nur `friend_likes` (MVP, umgesetzt im vorherigen Schritt),
  „später erweitern um Genre-Präferenzen: In Cloud Function Nutzer-Historie analysieren und
  `user_preferences` aktualisieren". Dieser Schritt setzt diese Erweiterung um.
- **Mit dem Product Owner abgestimmte Werte** (die Master-Spezifikation nennt für diese Punkte
  keine konkrete Zahl/Formel – erfunden wurde hier bewusst nichts, sondern vor der Implementierung
  explizit nachgefragt):
  - **Genre-Präferenz-Speicherung:** TMDB-Genre-IDs werden zusätzlich auf jedem Swipe-Dokument
    gespeichert (`genre_ids`, nur numerische IDs, keine vollständigen Filmdaten), statt sie bei
    jeder Berechnung erneut von TMDB abzufragen.
  - **Anti-Boost-Umfang:** beide in §7 genannten Kriterien sind umgesetzt – „gleiches Genre" (dieser
    Schritt) und „gleicher Hauptdarsteller" (siehe „Cast-Anti-Boost" unten).
  - **Zeitbasierter Verfall:** linearer Verfall über 30 Tage (Gewicht 1,0 am Tag des Likes, linear
    auf 0 nach 30 Tagen) – gilt für die Genre-Präferenz, nicht für den (weiterhin ungedämpften)
    Freundes-Boost, den bereits der vorherige MVP-Schritt getestet hat, und nicht für die beiden
    Anti-Boost-Faktoren (§7 nennt den Verfall ausdrücklich nur für „ältere Likes").
  - „**Oft geliked**" (Schwelle für den Genre-Grund-Boost): die Top-3-Genres eines Users nach
    zeitverfallsgewichteter Like-Anzahl.
  - **Freundes-Boost bleibt kumulativ** (+40 je Freund, der einen Film geliked hat, nicht nur
    einmalig pro Film) – das entspricht der bereits vor diesem Schritt getesteten MVP-Priorisierung
    (ein Film mit zwei Freundes-Likes rangiert nachweislich vor einem mit nur einem) und durfte
    durch diese Erweiterung nicht kaputtgehen.
- **Architektur (Genre-Präferenz/Anti-Boost, global pro User):** neue Collection
  `user_preferences/{uid}` (§17.4-Schema: `genre_affinity`, dazu als sinnvolle, im Schema
  ausdrücklich offen gelassene Erweiterung `disliked_genres` und ein vorberechnetes
  `top_genres`), ausschließlich serverseitig gepflegt von der neuen Cloud Function
  `functions/userPreferences.js` (`onSwipeWrittenForPreferences`, zweiter, unabhängiger Trigger auf
  denselben `groups/{groupId}/swipes/{swipeId}`-Pfad wie die Match-Erkennung). Wertet bei jedem
  Swipe-Schreibvorgang (Anlegen, Ändern, **und Löschen** – wichtig für „Watchlist entfernen") die
  komplette, gruppenübergreifende Swipe-Historie des betroffenen Users per `collectionGroup`-Query
  neu aus (voller Rescan statt inkrementellem Zähler, damit ein gelöschter Swipe die Präferenzen
  automatisch korrekt aktualisiert, ohne eine separate Dekrement-Logik zu brauchen). Der Client
  liest dieses Dokument nur (`UserPreferencesRepository`, neuer Provider
  `userPreferencesRepositoryProvider`) – berechnet nichts selbst nach.
- **Architektur (Freundes-Likes, weiterhin gruppenscoped, unverändert aus dem MVP-Schritt):**
  `SwipeRepository.getGroupLikes(groupId)` → `countFriendLikes()` (`lib/utils/boost.dart`) → vom
  `SwipeQueueController` einmal pro Session-Aufbau berechnet.
- **Zusammenführung zum Gesamt-Score:** `computeBoostScore()`/`sortByBoostScore()`
  (`lib/utils/boost.dart`, reine, seiteneffektfreie Funktionen) kombinieren beide Quellen additiv
  exakt nach der §7-Formel und sortieren die bereits gefilterte, deduplizierte Kandidatenliste am
  Ende von `SwipeQueueController._fillQueue` um. Die alte MVP-Sortierung
  (`sortByFriendLikeBoost`/`ORDER BY friend_likes DESC, RANDOM()`) bleibt als eigenständige,
  weiterhin getestete Funktion erhalten (§18 beschreibt sie ausdrücklich als den zuerst umgesetzten
  Zwischenschritt), wird von der Warteschlange aber nicht mehr aufgerufen.
- **Zusammenspiel mit dem Filtersystem:** wie zuvor – der Boost sortiert ausschließlich innerhalb
  der bereits durch `MovieFilter` eingeschränkten und paginierten TMDB-Kandidaten um.
- **Was der Boost bewusst NICHT beeinflusst:** Die Match-Erkennung (`functions/matchEngine.js`)
  bleibt vollständig unabhängig – der Boost sortiert nur um, er löst nie selbst einen Match aus.
  Bereits geswipte Filme bleiben weiterhin ausgeschlossen; Pagination ist unverändert.
- **Datenmodell:** `groups/{groupId}/swipes/{uid}_{movieId}` bekommt ein neues, optionales Feld
  `genre_ids` (nach dem Anlegen unveränderlich, wie `movie_id`/`created_at`) – ältere Dokumente
  ohne dieses Feld werden robust als „keine Genres bekannt" gelesen, keine Migration nötig. Neue
  Collection `user_preferences/{uid}`.
- **Security:** `user_preferences/{userId}`: nur der eigene User darf lesen, **niemand** darf
  clientseitig schreiben (auch nicht der Owner selbst) – analog zu `groups/{groupId}/matches`, das
  aus demselben Grund ebenfalls ausschließlich serverseitig entsteht. `genre_ids` auf `swipes` ist
  typgeprüft (muss eine Liste sein, falls vorhanden) und nach dem Anlegen unveränderlich – dieselbe
  Rolle wie `movie_id`/`created_at`. Ein Nutzer kann über den Boost niemals selbst einen Match
  erzeugen und niemals Daten einer fremden Gruppe oder eines fremden Users in die eigene Berechnung
  einschleusen.

### Cast-Anti-Boost „gleicher Hauptdarsteller" (§7/§18)

- **Exakte Vorgabe (§7):** derselbe Satz wie beim Genre-Anti-Boost oben – „Ein Dislike senkt den
  Score ähnlicher Filme leicht (–10), gleiches Genre, gleicher Hauptdarsteller." Der Genre-Teil war
  bereits umgesetzt (siehe „Boost-Algorithmus" oben); dieser Schritt ergänzt den zweiten,
  gleichrangigen Kriterium.
- **Mit dem Product Owner abgestimmter Wert** (die Master-Spezifikation nennt keine Zahl, wie viele
  Cast-Einträge als „Hauptdarsteller" zählen – erfunden wurde hier bewusst nichts, sondern vor der
  Implementierung explizit nachgefragt): **die Top 3** Einträge aus TMDBs `/movie/{id}/credits`, das
  `cast`-Array ist dort bereits nach TMDBs eigenem `order`-Feld sortiert (0 = am prominentesten
  billed). Konsistent mit der bereits bestehenden „Top-3-Genres"-Regel für die Genre-Präferenz im
  selben Boost-System. Gilt symmetrisch für beide Seiten des Vergleichs (gedislikter Film UND
  Kandidat).
- **TMDB-Credits-Integration:** neuer `TmdbService.movieCredits(tmdbId)`-Endpunkt
  (`/movie/{id}/credits`, derselbe Bearer-Token/dieselbe Fehlerbehandlung wie alle anderen
  TMDB-Aufrufe – kein neuer API-Key, kein eigenes HTTP-Setup). `selectMainCastIds()`
  (`lib/models/movie_cast.dart`) wählt daraus die Top-3-Personen-IDs (robust gegenüber fehlenden/
  unvollständigen Cast-Daten – ein einzelner ungültiger Eintrag wird übersprungen statt die ganze
  Liste zu verwerfen, ein fehlendes `cast`-Array ergibt eine leere Liste statt eines Fehlers).
- **Caching/Performance:** `MovieRepository.getMainCastIds()` cached das Ergebnis pro `tmdbId`
  (gleiche, bereits bestehende, auf 100 Einträge begrenzte In-Memory-Cache-Strategie wie
  `getMovieDetails`/`getTrailer`) – ein Film wird über die App-Laufzeit höchstens einmal abgefragt.
  `SwipeQueueController._withCastIds()` reichert jede frisch von TMDB geladene Warteschlangen-Seite
  parallel an (`Future.wait`, begrenzt auf die durch `_maxPagesPerFill` gedeckelte Seitenzahl pro
  Auffüll-Vorgang – keine unkontrollierte Anzahl gleichzeitiger Requests). Schlägt der
  Credits-Abruf für einen einzelnen Film fehl (TMDB-Fehler, Rate-Limit, Timeout, ...), bleibt dieser
  Film trotzdem in der Warteschlange – nur ohne Cast-Anti-Boost-Signal für diesen einen Film; ein
  einzelner TMDB-Fehler blockiert nie die gesamte Swipe-Funktion.
- **Boost-Formel:** `computeBoostScore()`/`sortByBoostScore()` (`lib/utils/boost.dart`) bekommen
  einen zusätzlichen, zum Genre-Anti-Boost strukturell identischen Term: –10 je Hauptdarsteller des
  Kandidaten, der bereits unter den Top-3-Hauptdarstellern eines vom User disliketen Films war
  (presence-basiert wie beim Genre-Anti-Boost – wie oft ein Hauptdarsteller bereits vorkam, spielt
  keine Rolle, nur ob er überhaupt vorkommt; kann bei mehreren überschneidenden Hauptdarstellern
  entsprechend mehrfach abziehen). Alle zuvor abgestimmten Faktoren (Freundes-Likes, Genre-Präferenz,
  Genre-Anti-Boost, Rating, Zeitverfall, Zufall) bleiben unverändert.
- **Datenmodell:** `groups/{groupId}/swipes/{uid}_{movieId}` bekommt ein weiteres, optionales Feld
  `cast_ids` (exakter Spiegel von `genre_ids` – nach dem Anlegen unveränderlich, ältere Dokumente
  ohne dieses Feld werden robust als „keine Hauptdarsteller bekannt" gelesen). `user_preferences/{uid}`
  bekommt ein neues Feld `disliked_cast_ids` (exakter Spiegel von `disliked_genres` – Anzahl Dislikes
  pro Personen-ID, ohne Zeitverfall, ausschließlich serverseitig von
  `functions/userPreferences.js` gepflegt). Keine neue Collection nötig, kein vollständiger
  TMDB-Cast (Namen, Bilder, Rollen, ...) wird gespeichert – nur numerische Personen-IDs.
- **Security:** `cast_ids` auf `swipes` ist wie `genre_ids` typgeprüft und nach dem Anlegen
  unveränderlich, schreibbar nur über den eigenen Swipe. Ein Client könnte theoretisch ein
  frei erfundenes `cast_ids` mitschicken – das kann aber ausschließlich die eigene, persönliche
  Warteschlangen-Sortierung dieses einen Users verfälschen (dieselbe, bereits bei `genre_ids`
  akzeptierte Eigenschaft), niemals Daten anderer User, die Match-Erkennung
  (`functions/matchEngine.js` liest weder `genre_ids` noch `cast_ids`) oder `user_preferences`
  selbst beeinflussen – dieses Dokument bleibt vollständig serverseitig beschrieben
  (`allow write: if false`, unverändert).
- **UI:** keine – dieser Schritt ist rein serverseitig/algorithmisch, die Swipe-Oberfläche
  (`SwipeCard`, Warteschlange, Aktionen) bleibt für den Nutzer unverändert sichtbar.

### Super Swipe (§6/§15)

- **Exakte Vorgabe:** §6 (Swipe-System-Tabelle): „**Super Swipe** (Premium) | Besondere Empfehlung |
  Signalisiert der Gruppe: ‚Den will ich unbedingt sehen!' – erhöht Boost zusätzlich." §15 (Premium
  Abo) listet „Super Swipe" als eine der Premium-Vorteile. §17.4 sieht `swipe_type` bereits als
  5-wertiges Enum vor (`'like'|'dislike'|'skip'|'watchlist'|'super'`) – ein eigener, gleichrangiger
  Entscheidungstyp, kein Zusatz-Flag auf einem Like.
- **Mit dem Product Owner abgestimmte Punkte** (die Master-Spezifikation beantwortet diese nicht
  eindeutig – erfunden wurde hier bewusst nichts, sondern vor der Implementierung explizit
  nachgefragt):
  - **Boost-Bonus:** §6 nennt keinen Wert für „erhöht Boost zusätzlich" – dieser Teil ist **bewusst
    zurückgestellt**. Ein Super Swipe hat aktuell keinen Effekt auf `computeBoostScore`
    (`lib/utils/boost.dart`, unverändert).
  - **Match-Wirkung:** §8 definiert ein Match wörtlich nur über „Like". Ein Super Swipe **zählt wie
    ein Like** für die Match-Bedingung (`functions/matchEngine.js`: `decision === 'like' ||
    decision === 'super'`) – alle Mitglieder müssen weiterhin zugestimmt haben (like oder super),
    ein einzelner Super Swipe erzeugt für sich allein keinen Match.
  - **Kontingent:** kein Zähler, keine Reset-Logik – rein binäres Premium-Gating. Premium-Nutzer
    können Super Swipe beliebig oft verwenden, Free-Nutzer gar nicht (0). Die Master-Spezifikation
    nennt an keiner Stelle eine konkrete Zahl.
  - **Premium-Aktivierung:** §18 nennt RevenueCat für die Abo-Verwaltung, aber ein echter Kaufweg
    (App-Store-/Play-Store-Produkte, RevenueCat-SDK/-Account) existiert in dieser Umgebung nicht und
    ist nicht Teil dieses Schritts. Implementiert ist ausschließlich die **Lese-/Gating-Seite**
    (`PremiumRepository`, Firestore Rules) – analog zu Google/Apple Sign-In bleibt die tatsächliche
    Aktivierung offene externe Konfiguration.
- **Architektur:** `SwipeService.superSwipeMovie()` prüft `PremiumRepository.isPremium(uid)`, bevor
  überhaupt geschrieben wird (die Firestore Rules erzwingen dieselbe Prüfung serverseitig zusätzlich
  über `isPremium()`, niemals nur clientseitig vertraut) und delegiert dann an denselben
  `SwipeRepository.setSwipe()`-Pfad wie alle anderen Entscheidungen – keine zweite
  Speicher-Infrastruktur. `SwipeActionController.superSwipe()` existiert als vollständige,
  getestete Controller-Methode; **noch keine UI/Geste ruft sie auf** (siehe „Noch nicht
  implementiert" oben – die Master-Spezifikation beschreibt keine Interaktion dafür, die vier
  Wisch-Richtungen sind bereits belegt, ein Erfinden einer eigenen Geste war nicht Teil dieses
  Schritts).
- **Datenmodell:** `super` als fünfter, gleichrangiger `decision`-Wert auf
  `groups/{groupId}/swipes/{uid}_{movieId}` (exakt der in §17.4 vorgegebene String – `super` ist ein
  reserviertes Dart-Schlüsselwort, daher intern `SwipeDecision.superSwipe` mit einer expliziten
  `firestoreValue`-Zuordnung statt eines blinden `.name`). Neue Collection `premium_status/{uid}`
  (`is_premium: bool`).
- **Security:** `premium_status/{userId}`: nur der eigene User darf lesen, **niemand** darf
  clientseitig schreiben (auch nicht der Owner selbst) – analog zu `user_preferences`/`matches`.
  Firestore Rules erlauben `decision == 'super'` beim Anlegen/Aktualisieren eines Swipes
  ausschließlich, wenn `isPremium(request.auth.uid)` (ein serverseitiger `get()`-Check auf
  `premium_status/{uid}`) erfüllt ist – ein Client kann weder sein eigenes Kontingent noch seinen
  Premium-Status fälschen, und der Premium-Status eines anderen Users hat keinen Einfluss auf die
  eigene Berechtigung. Match-Erkennung bleibt atomar/idempotent (unveränderte Transaktion in
  `evaluateMatch`) – ein Super Swipe kann sie nicht umgehen oder doppelt auslösen.

## Match-System

### Datenmodell

| Collection | Zweck | Zugriff |
|---|---|---|
| `groups/{groupId}/matches/{movieId}` | Ein Film, den **alle** aktuellen Mitglieder geliked haben (`movie_id, member_uids, matched_at`) | lesbar für alle Mitglieder der Gruppe, **kein** Client-Schreibzugriff (`allow write: if false`) |

Kein vollständiges TMDB-JSON in Firestore, nur die Match-Referenz: `movie_id` (für die
TMDB-Auflösung), `member_uids` (Momentaufnahme der Mitglieder, die den Match ausgelöst haben,
sortiert für deterministische Vergleiche) und `matched_at` (Zeitpunkt der Entstehung). Die
Dokument-ID ist deterministisch die `movieId` – ein Film kann in einer Gruppe strukturell nie
doppelt als Match entstehen. Keine weiteren Felder (z. B. eine separate Like-/Mitgliederzahl) –
`member_uids.length` ergibt sich bereits aus dem Array, ein Extra-Feld wäre redundante, potenziell
veraltende Ableitung.

**Warum kategorisch kein Client-Schreibzugriff?** Ob ein Film ein Match ist, hängt von *allen*
aktuellen Swipes *aller* aktuellen Mitglieder ab. Firestore Security Rules können das nicht
sicher selbst prüfen – die Rules-Sprache kennt keine Aggregation/Schleife über eine beliebig
lange Collection (kein `COUNT`, kein `WHERE`, kein `for`), nur `get()`/`exists()` auf einzelne,
namentlich bekannte Pfade. Ein Client könnte also grundsätzlich ein manipuliertes Match-Dokument
einreichen, ohne dass eine reine Rule das zuverlässig erkennen könnte. Diese technische Grenze
wurde bewusst nicht mit einer unsicheren/getrickten Rule umgangen, sondern mit einer echten
serverseitigen Autorität gelöst (siehe unten). Die Security Rule selbst erlaubt Lesen nur
Gruppenmitgliedern und verbietet `create`/`update`/`delete` für jeden Client kategorisch
(`allow write: if false`) – unverändert seit der ersten Match-Implementierung, da diese
Anforderung bereits vollständig erfüllt war.

### Match-Erkennung (Cloud Function)

- **Serverseitige Erkennung:** `functions/index.js` registriert einen Firestore-Trigger
  `onSwipeWritten` auf `groups/{groupId}/swipes/{swipeId}`. Bei jedem Anlegen/Ändern eines Swipes
  lädt `functions/matchEngine.js` (mit Admin-Rechten, umgeht die Security Rules) die aktuelle
  Mitgliederliste der Gruppe sowie alle Swipes zum betroffenen Film und prüft **pro Mitglieds-UID
  einzeln**, ob eine Like-Entscheidung vorliegt – bewusst keine reine Like-*Anzahl* gegen die
  Mitgliederzahl, damit ein Swipe eines Users, der die Gruppe zwischenzeitlich verlassen hat, nie
  fälschlich mitzählt. Haben alle aktuellen Mitglieder geliked, wird das Match-Dokument einmalig
  und atomar (Firestore-Transaktion mit Existenz-Prüfung) angelegt – race-condition-sicher, kein
  doppeltes Dokument, selbst wenn mehrere Mitglieder nahezu gleichzeitig liken oder derselbe
  Trigger (Cloud Functions garantieren nur „at-least-once") mehrfach/parallel ausgeführt wird.
- **Client darf niemals selbst matchen:** nur die Cloud Function (Admin-SDK) kann Match-Dokumente
  erzeugen. Es gibt bewusst kein `match_service.dart` mit einer Schreib-/Erzeugungs-Methode, da
  eine clientseitige „Match erzeugen"-Funktion ohnehin wirkungslos wäre.
- **Endgültiges Ergebnis:** Ändert ein Mitglied seine Bewertung, nachdem ein Match bereits
  entstanden ist (Like → Dislike), oder verlässt es die Gruppe, bleibt das bestehende
  Match-Dokument unverändert bestehen – ein Match ist ein dauerhafter Beleg, kein flüchtiger
  Zustand, der bei einer Meinungsänderung wieder verschwindet (analog zu einem „Match" in
  vergleichbaren Swipe-Apps). Solange ein Film hingegen noch **nicht** gematcht ist, wird jede
  Bewertungsänderung korrekt in die laufende Auswertung einbezogen (Like → Dislike verhindert das
  Zustandekommen, Dislike → Like kann es auslösen).

### Push-Verhalten

Matches nutzen dieselbe Push-Infrastruktur wie Freundschaftsanfragen, Gruppeneinladungen und
Chat-Nachrichten (siehe „Push-Notifications" unten) – keine zweite, parallele Benachrichtigungs-
oder Duplikat-Schutz-Architektur. `functions/notifyMatch.js` reagiert auf das `onCreate` des
Match-Dokuments und informiert alle aktuellen Mitglieder der Gruppe („Neuer Match!" + Gruppenname).
Der Duplikat-Schutz läuft über dieselbe `claimNotification()`-Transaktion wie bei den anderen drei
Ereignistypen: da das Match-Dokument selbst bereits einmalig/atomar angelegt wird (siehe oben),
kann `onMatchCreated` ohnehin nur einmal pro Match feuern – `claimNotification()` sichert
zusätzlich gegen die „at-least-once"-Zustellung von Cloud Functions ab, damit trotzdem nie zwei
Notification-Runden für dasselbe Match verschickt werden.

### UI

- **Echtzeit-Anzeige:** `groupMatchesProvider(groupId)` (Riverpod `StreamProvider`) hält die
  Match-Liste einer Gruppe live aktuell (`MatchRepository.watchMatches`, Firestore-Snapshot-
  Stream, neueste zuerst nach `matched_at`) – kein manuelles Neuladen nötig.
- **Gruppen-Matches:** Ein „Matches"-Bereich in `GroupDetailScreen` zeigt die Match-Karten
  (`MatchCard`) der jeweiligen Gruppe. Ohne Matches ein ehrlicher Empty State „Noch kein
  gemeinsamer Film." – keine Fake-Karten.
- **Globaler „Matches"-Tab:** `MatchesScreen` (bisher Platzhalter aus Schritt 1) zeigt jetzt echte,
  gruppenübergreifende Match-Daten als Grid, sortiert über alle Gruppen hinweg nach `matched_at`
  (neueste zuerst). `allMyMatchesProvider` (`lib/providers/match_provider.dart`) kombiniert dafür
  reaktiv `myGroupsProvider` mit je einem `groupMatchesProvider(groupId)` pro Gruppe – reine
  Riverpod-Provider-Komposition, kein `MatchService` nötig (siehe Doc-Kommentar dort). Jede Karte
  zeigt zusätzlich den Namen der Gruppe, in der der Match entstanden ist. Ohne Matches derselbe
  ehrliche Empty State wie in der Gruppenansicht.
- **Match-Karte (`MatchCard`):** Poster, Titel, Erscheinungsjahr, Bewertung und Genres – echte
  TMDB-Daten über das bestehende `movieDetailsProvider`, keine zweite API-Anbindung. Jede Karte
  lädt ihre TMDB-Daten unabhängig von den anderen, damit ein einzelner TMDB-Fehler nie die
  restliche Liste blockiert. Die Karte selbst legt keine feste Breite mehr fest (nötig für die
  duale Verwendung: feste Breite in der horizontalen Gruppenliste, variable Breite im
  gruppenübergreifenden Grid) – die Breite bestimmt jeweils der Aufrufer.
- **TMDB-Auflösung:** Das Match-Dokument selbst enthält nur `movie_id` – Titel, Poster, Jahr,
  Bewertung und Genres werden bei jedem Laden frisch von TMDB nachgeladen. Ist TMDB für einen
  einzelnen Film nicht erreichbar, bleibt der Match trotzdem sichtbar (aus Firestore geladen) mit
  einem ehrlichen Lade-/Fehlerzustand auf der Karte (Ladeindikator bzw. Fehler-Icon) – kein Block
  der restlichen Liste, keine Fake-Daten als Ersatz.
- **Reaktion beim Swipen:** Entsteht während einer laufenden Swipe-Session ein neues Match, zeigt
  `GroupSwipeScreen` einen „Match! 🍿"-Dialog mit Poster (reagiert auf `groupMatchesProvider`,
  nicht auf eine eigene, redundante Zähllogik in der UI). Die Match-*Erkennung* selbst bleibt
  vollständig serverseitig – `SwipeCard` und die Swipe-Business-Logik aus Schritt 6 wurden dafür
  nicht verändert.
- Antippen einer Match-Karte (in der Gruppen- wie in der globalen Ansicht) öffnet die bestehende
  `MovieDetailScreen` (Poster, Backdrop, Titel, Beschreibung, Genres, Bewertung, Laufzeit,
  Erscheinungsjahr, Streaming-Anbieter) – bewusst keine zweite, redundante „Match-Detail"-Seite.
- **Match-Systemnachricht im Chat:** `functions/postMatchChatMessage.js` postet, ausgelöst vom
  selben `onMatchCreated`-Trigger wie `notifyMatch.js`, aber in einem eigenen `try/catch` und mit
  einem eigenen `claimNotification`-Idempotenz-Marker (`chat_message_posted_at` statt
  `notified_at` auf demselben Match-Dokument), eine Systemnachricht (`type: 'match', movie_id`) in
  `groups/{groupId}/messages`. `MessageBubble` rendert diesen Typ als zentrierte Karte mit
  TMDB-Poster/Titel (`movieDetailsProvider`) statt als normale Sprechblase; Antippen öffnet die
  Filmdetails. Siehe „Datenmodell (Chat)" und „Chat-Funktion" unten für Details.
- **Nicht Teil des Match-Systems:** Filmabend-/Terminplanung.

### Offene externe Deployments

Keine – die Firestore Rules, die Cloud Functions und der globale Matches-Tab sind vollständig
funktionsfähig ohne weitere externe Konfiguration. Die offenen externen Konfigurationen des
Gesamtprojekts (Google/Apple Sign-In, APNs) betreffen nicht das Match-System und sind unter
„Offene externe Konfiguration" weiter unten aufgeführt.

## Datenmodell (Chat)

| Collection | Zweck | Zugriff |
|---|---|---|
| `groups/{groupId}/messages/{messageId}` | Eine Chat-Nachricht: entweder eine Text-Nachricht (`sender_uid, text, created_at`) oder eine serverseitige Match-Systemnachricht (`type: 'match', movie_id, created_at`) | Text-Nachrichten: lesbar/anlegbar für Mitglieder der Gruppe, kein Update/Delete. Match-Systemnachrichten: ausschließlich per Admin-SDK durch `postMatchChatMessage.js` erzeugt, kein Client-Schreibzugriff möglich |

Firestore-Auto-ID pro Nachricht. Bewusst **keine** `sender_name`/`sender_profile_picture`-Kopie im
Dokument: beide lassen sich zuverlässig über das bestehende `public_profiles/{uid}` nachschlagen
(`publicProfileProvider`) – eine Kopie hier wäre unnötige Redundanz und könnte veralten, wenn sich
Name/Bild später ändern. `created_at` wird ausschließlich serverseitig über
`FieldValue.serverTimestamp()` gesetzt – die lokale Gerätezeit ist keine vertrauenswürdige Quelle;
die Security Rule erzwingt das (`created_at == request.time`), ein client-gesetzter Zeitstempel
wird abgelehnt.

**Match-Systemnachrichten (`type: 'match'`):** Bestehende Dokumente ohne `type`-Feld gelten
weiterhin als normale Text-Nachricht (`ChatMessageType.text`, Default) – vollständig
rückwärtskompatibel. Enthalten bewusst nur `movie_id`, keinen Filmtitel: Cloud Functions haben
keinen TMDB-Zugriff und sollen auch keinen bekommen (dasselbe Architekturprinzip wie beim
Match-Dokument selbst), der Client löst den Film über `movieDetailsProvider` auf. Die bestehende
`create`-Rule für Text-Nachrichten (`keys().hasOnly(['sender_uid', 'text', 'created_at'])`) lehnt
jeden Versuch eines Clients, ein `type: 'match'`-Dokument zu fälschen, bereits strukturell ab –
keine separate Rule nötig, siehe zwei explizite Negativ-Tests in `messages.rules.test.mjs`.

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
- **Match-Systemnachrichten:** `postMatchChatMessage.js` (eigener `try/catch` neben
  `notifyMatch.js` im selben `onMatchCreated`-Trigger, eigener `claimNotification`-Idempotenz-
  Marker) postet automatisch eine Systemnachricht, sobald ein Match entsteht. `MessageBubble`
  rendert diese als zentrierte Karte mit TMDB-Poster/Titel statt als normale Sprechblase; Antippen
  öffnet `MovieDetailScreen`. `notifyChatMessage.js` (Push für normale Nachrichten) ignoriert
  Systemnachrichten automatisch (fehlender `sender_uid` lässt die Funktion früh zurückkehren) –
  keine doppelte oder fälschliche Push-Notification dafür.
- **Nicht Teil dieses Schritts:** Filmabend-/Terminplanung, RSVP, Watch Party.

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
  (prüft/setzt standardmäßig ein `notified_at`-Feld auf dem jeweiligen Quelldokument) – nur der
  erste erfolgreiche Aufruf sendet tatsächlich, jeder weitere bricht sauber ab. Kein naives „ein
  Trigger = garantiert eine Notification". Der optionale `field`-Parameter erlaubt mehrere
  unabhängige Claims auf demselben Dokument (z. B. Push-Notification `notified_at` und
  Chat-Systemnachricht `chat_message_posted_at` auf demselben Match-Dokument) – jede Aktion
  beansprucht ihr eigenes Marker-Feld, ohne sich gegenseitig zu blockieren.
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
  Genre-Namen-Auflösung), Watch Providers (Streaming-Verfügbarkeit), Watch Provider List
  (Plattform-Filter), Movie Videos (Trailer).
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

### Trailer-Button (§9)

- **Datenquelle:** ausschließlich TMDB (`/movie/{id}/videos`, §17.3: "TMDB API – ... Trailer-Links")
  - keine eigene/erfundene Trailerquelle. `MovieTrailer.selectFromTmdbJson`
  (`lib/models/movie_trailer.dart`) wählt daraus gezielt einen `site == 'YouTube'` **und**
  `type == 'Trailer'` Eintrag aus (Teaser/Clips/Featurettes und andere Plattformen wie Vimeo werden
  ignoriert); bei mehreren Treffern wird der offizielle bevorzugt, danach der zuletzt
  veröffentlichte. Liefert TMDB keinen passenden Trailer, ist das Ergebnis `null` - ein normaler,
  kein fehlerhafter Zustand.
- **Architektur:** `TmdbService.movieVideos` → `MovieRepository.getTrailer` (In-Memory-Cache wie
  bei Filmdetails/Genres, kein Firestore) → `movieTrailerProvider` → `_TrailerButton` in
  `MovieDetailScreen`. Keine zweite TMDB-Integration, keine neue Movie-Datenbank.
- **UI:** Der „Trailer ansehen"-Button erscheint **nur**, wenn TMDB tatsächlich einen Trailer
  liefert - kein Platzhalter, keine sichtbare Fehlermeldung bei fehlendem Trailer (Ladezustand und
  TMDB-Fehler blenden den Button ebenfalls einfach aus, statt die restliche Filmdetailseite zu
  blockieren). Antippen öffnet `TrailerDialog` - eingebettete Wiedergabe **als Popup** (§9: "öffnet
  den YouTube-Trailer als kleines Popup"), kein externes Öffnen der YouTube-App oder des Browsers.
- **Package:** `youtube_player_flutter` (§18 nennt dieses Package explizit als Beispiel-Umsetzung),
  gebaut auf der offiziellen YouTube-iFrame-API - kein YouTube-API-Key nötig, keine Secrets im
  Client. Der YouTube-Video-Key wird nur so lange gehalten, wie für Anzeige/Wiedergabe nötig
  (Repository-Cache, kein Firestore-Feld).
- **Erreichbarkeit während des Swipens:** Ein Antippen (kein Ziehen) der `SwipeCard` in
  `GroupSwipeScreen` öffnet dieselbe `MovieDetailScreen` samt Trailer-Button - der Trailer ist damit
  auch während einer laufenden Swipe-Session erreichbar, ohne eine zweite Trailer-Implementierung
  auf der Karte selbst. Tap und Wisch-Geste teilen sich denselben `GestureDetector`; Flutters
  Gesten-Arena entscheidet zuverlässig zwischen beiden (ein Ziehen über die Wisch-Schwelle löst
  ausschließlich den Swipe aus, nie zusätzlich die Navigation) - mit dedizierten Widget-Tests
  abgesichert (`group_swipe_movie_detail_test.dart`).

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
