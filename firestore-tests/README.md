# Security Rules Tests

Testet die tatsächlichen `../firestore.rules` und `../storage.rules` gegen die echten
lokalen Firebase-Emulatoren (nicht gegen ein vereinfachtes Fake, das `exists()`,
`resource` etc. nicht unterstützt).

## Voraussetzungen

- Node.js
- Firebase CLI (`npm install -g firebase-tools`)
- Java (für die Emulatoren)

## Ausführen

```bash
# Einmalig: Emulator-JARs herunterladen
firebase setup:emulators:firestore
firebase setup:emulators:storage

# Terminal 1: Emulatoren im Repo-Root starten
firebase emulators:start --only firestore,storage --project film2watch-rules-test

# Terminal 2: Tests ausführen
cd firestore-tests
npm install
npm test
```
