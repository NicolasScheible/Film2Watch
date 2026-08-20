# Cloud Functions – Gruppen-Match-Erkennung

Serverseitige Match-Erkennung (Schritt 7). `onSwipeWritten` (`index.js`) ist ein
Firestore-Trigger auf `groups/{groupId}/swipes/{swipeId}`, der bei jeder Änderung
`matchEngine.js` mit Admin-Rechten ausführt. Die Firestore Security Rules verbieten
jedem Client jeglichen Schreibzugriff auf `groups/{groupId}/matches/{movieId}`
kategorisch – nur diese Cloud Function (Admin-SDK, umgeht die Rules) darf
Match-Dokumente erzeugen.

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

# Terminal 2: echte End-to-End-Tests gegen den laufenden Trigger
cd functions
FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 GCLOUD_PROJECT=film2watch-rules-test npm test
```

Die Tests schreiben echte Swipe-Dokumente über das Admin-SDK, warten auf den echten
(asynchronen) Cloud-Function-Trigger und prüfen das entstehende bzw. bewusst
ausbleibende Match-Dokument – kein isoliertes Mocken der Trigger-Logik.

## Deployment

```bash
firebase deploy --only functions
```

Erfordert den **Blaze-Tarif (Pay-as-you-go)** für das Firebase-Projekt – Cloud
Functions laufen nicht auf dem kostenlosen Spark-Tarif.
