# Firestore Security Rules Tests

Testet die tatsächliche `../firestore.rules` gegen den echten lokalen
Firestore-Emulator (nicht gegen ein vereinfachtes Fake, das `exists()`,
`resource` etc. nicht unterstützt).

## Voraussetzungen

- Node.js
- Firebase CLI (`npm install -g firebase-tools`)
- Java (für den Firestore-Emulator)

## Ausführen

```bash
# Einmalig: Emulator-JAR herunterladen
firebase setup:emulators:firestore

# Terminal 1: Emulator im Repo-Root starten
firebase emulators:start --only firestore --project film2watch-rules-test

# Terminal 2: Tests ausführen
cd firestore-tests
npm install
npm test
```
