import { readFileSync } from 'node:fs';
import { after, before, describe, it } from 'node:test';
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';
import firebase from 'firebase/compat/app';
import 'firebase/compat/firestore';

// `context.firestore()` liefert eine Compat-Firestore-Instanz (siehe
// @firebase/rules-unit-testing) - FieldValue.serverTimestamp() kommt daher
// vom Compat-Namespace, nicht aus dem modularen `firebase/firestore`-Paket.
const serverTimestamp = () => firebase.firestore.FieldValue.serverTimestamp();

// Testet die tatsächliche firestore.rules-Datei des Repos gegen den echten
// lokalen Firestore-Emulator für den Gruppenchat (Schritt 8). Eigene
// Gruppen-ID ("chatgroup1"), um Überschneidungen mit anderen, parallel
// laufenden Test-Dateien zu vermeiden, die ebenfalls Gruppen-Fixtures
// anlegen (z. B. groups.rules.test.mjs/swipes.rules.test.mjs).

let testEnv;
const now = () => new Date();

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'film2watch-rules-test',
    firestore: {
      rules: readFileSync('../firestore.rules', 'utf8'),
      host: '127.0.0.1',
      port: 8080,
    },
  });

  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await db.doc('groups/chatgroup1').set({
      id: 'chatgroup1',
      name: 'Filmabend',
      photo_url: null,
      created_by: 'alice',
      created_at: now(),
      updated_at: now(),
    });
    await db.doc('groups/chatgroup1/members/alice').set({ uid: 'alice', role: 'admin', joined_at: now() });
    await db.doc('groups/chatgroup1/members/bob').set({ uid: 'bob', role: 'member', joined_at: now() });
    // carol ist kein Mitglied von chatgroup1.
    await db.doc('groups/chatgroup1/messages/msg1').set({
      sender_uid: 'alice',
      text: 'Hallo zusammen!',
      created_at: now(),
    });
  });
});

after(async () => {
  await testEnv.cleanup();
});

describe('groups/{groupId}/messages/{messageId}', () => {
  it('lehnt unauthentifiziertes Lesen ab', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(db.collection('groups/chatgroup1/messages').get());
  });

  it('lehnt unauthentifiziertes Erstellen ab', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(
      db.collection('groups/chatgroup1/messages').add({
        sender_uid: 'ghost',
        text: 'Hi',
        created_at: now(),
      }),
    );
  });

  it('erlaubt einem Gruppenmitglied das Lesen', async () => {
    const db = testEnv.authenticatedContext('bob').firestore();
    await assertSucceeds(db.collection('groups/chatgroup1/messages').get());
  });

  it('erlaubt einem Gruppenmitglied, eine Nachricht zu erstellen', async () => {
    const db = testEnv.authenticatedContext('bob').firestore();
    await assertSucceeds(
      db.collection('groups/chatgroup1/messages').add({
        sender_uid: 'bob',
        text: 'Wie wär’s mit Freitag?',
        created_at: serverTimestamp(),
      }),
    );
  });

  it('lehnt das Lesen durch ein Nicht-Mitglied ab', async () => {
    const db = testEnv.authenticatedContext('carol').firestore();
    await assertFails(db.collection('groups/chatgroup1/messages').get());
  });

  it('lehnt das Erstellen durch ein Nicht-Mitglied ab', async () => {
    const db = testEnv.authenticatedContext('carol').firestore();
    await assertFails(
      db.collection('groups/chatgroup1/messages').add({
        sender_uid: 'carol',
        text: 'Ich bin gar nicht in der Gruppe',
        created_at: now(),
      }),
    );
  });

  it('lehnt es ab, dass User A im Namen von User B schreibt', async () => {
    const db = testEnv.authenticatedContext('bob').firestore();
    await assertFails(
      db.collection('groups/chatgroup1/messages').add({
        sender_uid: 'alice',
        text: 'Ich tue so, als wäre ich alice',
        created_at: now(),
      }),
    );
  });

  it('lehnt eine fremd erfundene sender_uid ab', async () => {
    const db = testEnv.authenticatedContext('bob').firestore();
    await assertFails(
      db.collection('groups/chatgroup1/messages').add({
        sender_uid: 'nicht-existierender-user',
        text: 'Ungültiger Absender',
        created_at: now(),
      }),
    );
  });

  it('lehnt es ab, dass ein Mitglied eine fremde Nachricht ändert', async () => {
    const db = testEnv.authenticatedContext('bob').firestore();
    await assertFails(db.doc('groups/chatgroup1/messages/msg1').update({ text: 'Manipuliert' }));
  });

  it('lehnt es ab, dass ein Mitglied eine fremde Nachricht löscht', async () => {
    const db = testEnv.authenticatedContext('bob').firestore();
    await assertFails(db.doc('groups/chatgroup1/messages/msg1').delete());
  });

  it('lehnt es ab, dass der Absender die eigene Nachricht nachträglich ändert', async () => {
    const db = testEnv.authenticatedContext('alice').firestore();
    await assertFails(db.doc('groups/chatgroup1/messages/msg1').update({ text: 'Bearbeitet' }));
  });

  it('lehnt leeren Text ab', async () => {
    const db = testEnv.authenticatedContext('bob').firestore();
    await assertFails(
      db.collection('groups/chatgroup1/messages').add({
        sender_uid: 'bob',
        text: '',
        created_at: now(),
      }),
    );
  });

  it('lehnt zu langen Text ab', async () => {
    const db = testEnv.authenticatedContext('bob').firestore();
    await assertFails(
      db.collection('groups/chatgroup1/messages').add({
        sender_uid: 'bob',
        text: 'x'.repeat(2001),
        created_at: now(),
      }),
    );
  });

  it('lehnt einen client-gesetzten created_at-Wert ab (kein request.time)', async () => {
    const db = testEnv.authenticatedContext('bob').firestore();
    await assertFails(
      db.collection('groups/chatgroup1/messages').add({
        sender_uid: 'bob',
        text: 'Gefälschter Zeitstempel',
        created_at: new Date('2020-01-01'),
      }),
    );
  });

  it('lehnt zusätzliche, nicht vorgesehene Felder ab', async () => {
    const db = testEnv.authenticatedContext('bob').firestore();
    await assertFails(
      db.collection('groups/chatgroup1/messages').add({
        sender_uid: 'bob',
        text: 'Mit Extra-Feld',
        created_at: now(),
        sender_name: 'Bob (untergeschoben)',
      }),
    );
  });
});
