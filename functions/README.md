# Cloud Functions – Match-Erkennung + Push-Notifications

Serverseitige Logik in zwei Bereichen:

- **Match-Erkennung (Schritt 7):** `onSwipeWritten` (`index.js`) ist ein Firestore-Trigger
  auf `groups/{groupId}/swipes/{swipeId}`, der bei jeder Änderung `matchEngine.js` mit
  Admin-Rechten ausführt. Die Firestore Security Rules verbieten jedem Client jeglichen
  Schreibzugriff auf `groups/{groupId}/matches/{movieId}` kategorisch – nur diese Cloud
  Function (Admin-SDK, umgeht die Rules) darf Match-Dokumente erzeugen.
- **Push-Notifications (Schritt 9):** vier Firestore-Trigger (`onFriendRequestCreated`,
  `onGroupInvitationCreated`, `onMatchCreated`, `onChatMessageCreated`) versenden über
  `notifications.js` (`sendToUsers`/`claimNotification`) und die vier `notify*.js`-Module
  Push-Notifications an die jeweils richtigen Empfänger. Auch das läuft ausschließlich
  serverseitig – der Flutter-Client kann nie direkt an andere Nutzer senden.

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

- `test/matchEngine.test.mjs`: echte End-to-End-Tests gegen den laufenden Trigger - Swipes
  werden real in Firestore geschrieben, der echte Cloud-Function-Trigger läuft mit, und es
  wird auf das entstehende (oder ausbleibende) Match-Dokument gewartet.
- `test/notifications.test.mjs`: testet die Notification-*Logik* (Empfänger-Ermittlung,
  Ausschluss des Absenders, Duplikat-Schutz, Cleanup ungültiger Tokens) direkt gegen den
  echten Firestore-Emulator, aber mit einem injizierten Fake-Messaging-Client statt echtem
  FCM-Versand - es gibt keinen "Firebase Cloud Messaging Emulator", und ohne echte
  Gerätetokens/Google-Cloud-Credentials wäre ein echter Versand in dieser Umgebung ohnehin
  nicht sinnvoll testbar.

## Deployment

```bash
firebase deploy --only functions
```

Erfordert den **Blaze-Tarif (Pay-as-you-go)** für das Firebase-Projekt – Cloud
Functions laufen nicht auf dem kostenlosen Spark-Tarif.
