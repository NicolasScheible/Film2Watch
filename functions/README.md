# Cloud Functions – Match-Erkennung + Push-Notifications + Filmabend-Abstimmung

Serverseitige Logik in drei Bereichen:

- **Match-Erkennung:** `onSwipeWritten` (`index.js`) ist ein Firestore-Trigger
  auf `groups/{groupId}/swipes/{swipeId}`, der bei jeder Änderung `matchEngine.js` mit
  Admin-Rechten ausführt. Die Firestore Security Rules verbieten jedem Client jeglichen
  Schreibzugriff auf `groups/{groupId}/matches/{movieId}` kategorisch – nur diese Cloud
  Function (Admin-SDK, umgeht die Rules) darf Match-Dokumente erzeugen.
- **Push-Notifications:** Firestore-Trigger (`onFriendRequestCreated`,
  `onGroupInvitationCreated`, `onMatchCreated`, `onChatMessageCreated`, `onMovieNightCreated`,
  `onMoviePollCreated`, `onMoviePollResolved`) versenden über `notifications.js`
  (`sendToUsers`/`claimNotification`) und die jeweiligen `notify*.js`-Module Push-Notifications
  an die jeweils richtigen Empfänger. Auch das läuft ausschließlich serverseitig – der
  Flutter-Client kann nie direkt an andere Nutzer senden.
- **Filmabend-Abstimmung (§21):** `resolveMoviePolls` (`index.js`) ist eine Scheduled Function
  (alle 5 Minuten), die `moviePollEngine.js: resolveDuePolls` mit Admin-Rechten ausführt - findet
  alle Abstimmungen mit erreichter Deadline, ermittelt den Gewinner (meiste Stimmen, bei
  Gleichstand der früheste Termin) und legt bei einem Gewinner automatisch einen
  `movie_nights`-Eintrag an. Die Firestore Security Rules verbieten jedem Client das Setzen von
  `status`/`winning_option_id`/`result_movie_night_id` auf einer Abstimmung kategorisch – nur
  diese Cloud Function darf eine Abstimmung schließen.

## Voraussetzungen

- Node.js
- Firebase CLI (`npm install -g firebase-tools`)
- Java (für den Firestore-Emulator)

## Tests ausführen

```bash
# Einmalig
cd functions
npm install

# Terminal 1: Firestore- + Functions-Emulator im Repo-Root starten
firebase emulators:start --only firestore,functions --project film2watch-rules-test

# Terminal 2: Tests
cd functions
FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 GCLOUD_PROJECT=film2watch-rules-test npm test
```

In Umgebungen mit einem erzwungenen HTTP(S)-Proxy (z. B. `HTTPS_PROXY`/`https_proxy` gesetzt):
der Functions-Emulator registriert seine Firestore-Trigger über einen lokalen HTTP-Request an
`127.0.0.1`. Manche Proxy-Clients in `firebase-tools` respektieren `NO_PROXY` dabei nicht
zuverlässig und routen auch diesen rein lokalen Request durch den Proxy, was je nach
Proxy-Policy zu `Error adding firestore function: ... Unable to parse JSON` führt (der Proxy
antwortet mit einer Klartext-Fehlermeldung statt JSON). Abhilfe: `HTTPS_PROXY`/`https_proxy`/
`HTTP_PROXY`/`http_proxy` ausschließlich für den `firebase emulators:start`-Prozess entfernen
(z. B. `env -u HTTPS_PROXY -u https_proxy -u HTTP_PROXY -u http_proxy firebase emulators:start
...`) - unschädlich, weil dieser Prozess ausschließlich mit sich selbst über `127.0.0.1`
kommuniziert, was `NO_PROXY` ohnehin bereits als Ausnahme vorsieht.

- `test/matchEngine.test.mjs`: echte End-to-End-Tests gegen den laufenden Trigger - Swipes
  werden real in Firestore geschrieben, der echte Cloud-Function-Trigger läuft mit, und es
  wird auf das entstehende (oder ausbleibende) Match-Dokument gewartet.
- `test/notifications.test.mjs`: testet die Notification-*Logik* (Empfänger-Ermittlung,
  Ausschluss des Absenders, Duplikat-Schutz, Cleanup ungültiger Tokens) direkt gegen den
  echten Firestore-Emulator, aber mit einem injizierten Fake-Messaging-Client statt echtem
  FCM-Versand - es gibt keinen "Firebase Cloud Messaging Emulator", und ohne echte
  Gerätetokens/Google-Cloud-Credentials wäre ein echter Versand in dieser Umgebung ohnehin
  nicht sinnvoll testbar.
- `test/moviePollEngine.test.mjs` (§21): testet `resolveOnePoll`/`resolveDuePolls` direkt (die
  exportierte Logik, die `resolveMoviePolls` unverändert aufruft) gegen den echten
  Firestore-Emulator - es gibt keinen sinnvollen Weg, eine zeitgesteuerte Function über einen
  Firestore-Write "warten zu lassen", daher der direkte Aufruf statt eines Trigger-Umwegs.
  Deckt Gewinner-Ermittlung, Gleichstand-Tie-Break, automatisches Anlegen des
  `movie_nights`-Eintrags und Idempotenz (kein doppelter Eintrag bei wiederholtem Lauf) ab.

Hinweis zur Emulator-Stabilität: je mehr Cloud Functions im selben Codebase registriert sind,
desto länger kann die Trigger-Verarbeitung eines einzelnen Firestore-Writes im lokalen Emulator
dauern (gemeinsamer Dispatch über alle Functions). `matchEngine.test.mjs` verwendet daher bewusst
großzügige Wartezeiten (`assertNoMatchAfterSettling`) statt möglichst knapper Werte.

## Backfill: User-Group-Index (`users/{uid}/groups/{groupId}`)

Einmaliges Skript, kein dauerhaftes Produkt-Feature (siehe README des Repository-Root,
Abschnitt "Architekturentscheidung"). Der Trigger `onGroupMemberWritten` pflegt den Index nur für
Mitgliedschaften, die nach seinem Deployment angelegt/gelöscht werden - bereits davor bestehende
Mitgliedschaften müssen einmalig nachgezogen werden:

```bash
cd functions

# Gegen den lokalen Emulator (z. B. zum Testen):
FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 GCLOUD_PROJECT=<project> \
  node scripts/backfillUserGroupIndex.js

# Gegen eine echte Firebase-Instanz: GOOGLE_APPLICATION_CREDENTIALS auf einen Service-Account-Key
# mit Firestore-Zugriff setzen und FIRESTORE_EMULATOR_HOST NICHT setzen. Nur nach ausdrücklicher,
# separater Freigabe ausführen - das Skript liest/schreibt dann echte Produktionsdaten.
GOOGLE_APPLICATION_CREDENTIALS=<pfad-zum-key> node scripts/backfillUserGroupIndex.js
```

Idempotent: ein wiederholter Lauf überschreibt bestehende, korrekte Einträge lediglich mit sich
selbst und erzeugt keine doppelten oder falschen Daten. Test: `functions/test/backfillUserGroupIndex.test.mjs`.

## Deployment

```bash
firebase deploy --only functions
```

Erfordert den **Blaze-Tarif (Pay-as-you-go)** für das Firebase-Projekt – Cloud
Functions laufen nicht auf dem kostenlosen Spark-Tarif.
