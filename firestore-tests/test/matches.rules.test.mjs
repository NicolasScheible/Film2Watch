import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { after, before, describe, it } from 'node:test';
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';

// Testet die tatsächliche firestore.rules-Datei des Repos gegen den echten
// lokalen Firestore-Emulator für Gruppen-Matches (Schritt 7). Match-Dokumente
// dürfen NIEMALS von einem Client geschrieben werden - nur die serverseitige
// Cloud Function (Admin-SDK, umgeht Rules komplett) darf das. Diese Tests
// verifizieren ausschließlich die Rules-Seite (Lesen für Mitglieder,
// Schreiben kategorisch verboten); die eigentliche Match-Erkennungslogik
// wird in `functions/test/matchEngine.test.mjs` getestet.

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
    await db.doc('groups/mgroup1').set({
      id: 'mgroup1',
      name: 'Filmabend',
      photo_url: null,
      created_by: 'alice',
      created_at: now(),
      updated_at: now(),
    });
    await db.doc('groups/mgroup1/members/alice').set({ uid: 'alice', role: 'admin', joined_at: now() });
    await db.doc('groups/mgroup1/members/bob').set({ uid: 'bob', role: 'member', joined_at: now() });
    // carol ist kein Mitglied von mgroup1.

    // Bereits bestehendes, "echtes" Match - simuliert das Ergebnis der
    // Cloud Function, ohne die Function selbst hier auszuführen.
    await db.doc('groups/mgroup1/matches/550').set({
      movie_id: 550,
      member_uids: ['alice', 'bob'],
      matched_at: now(),
    });
  });
});

after(async () => {
  await testEnv.cleanup();
});

describe('groups/{groupId}/matches/{matchId}', () => {
  it('lehnt unauthentifiziertes Lesen ab', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(db.doc('groups/mgroup1/matches/550').get());
  });

  it('lehnt unauthentifiziertes Schreiben ab', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(
      db.doc('groups/mgroup1/matches/999').set({
        movie_id: 999,
        member_uids: ['alice', 'bob'],
        matched_at: now(),
      }),
    );
  });

  it('erlaubt einem Gruppenmitglied das Lesen eines bestehenden Matches', async () => {
    const db = testEnv.authenticatedContext('bob').firestore();
    const snapshot = await assertSucceeds(db.doc('groups/mgroup1/matches/550').get());
    assert.equal(snapshot.data().movie_id, 550);
  });

  it('lehnt das Lesen durch ein Nicht-Mitglied ab', async () => {
    const db = testEnv.authenticatedContext('carol').firestore();
    await assertFails(db.doc('groups/mgroup1/matches/550').get());
  });

  it('lehnt es ab, dass ein normales Mitglied ein beliebiges Match anlegt', async () => {
    const db = testEnv.authenticatedContext('bob').firestore();
    await assertFails(
      db.doc('groups/mgroup1/matches/12345').set({
        movie_id: 12345,
        member_uids: ['alice', 'bob'],
        matched_at: now(),
      }),
    );
  });

  it('lehnt es ab, dass ein Admin ein beliebiges Match anlegt', async () => {
    // Auch der Gruppen-Admin darf keine Match-Dokumente erzeugen - das ist
    // ausschließlich der Cloud Function vorbehalten, nicht einer Rolle.
    const db = testEnv.authenticatedContext('alice').firestore();
    await assertFails(
      db.doc('groups/mgroup1/matches/54321').set({
        movie_id: 54321,
        member_uids: ['alice', 'bob'],
        matched_at: now(),
      }),
    );
  });

  it('lehnt es ab, dass ein Mitglied ein bestehendes Match verändert', async () => {
    const db = testEnv.authenticatedContext('bob').firestore();
    await assertFails(db.doc('groups/mgroup1/matches/550').update({ member_uids: ['bob'] }));
  });

  it('lehnt es ab, dass ein Mitglied ein bestehendes Match löscht', async () => {
    const db = testEnv.authenticatedContext('alice').firestore();
    await assertFails(db.doc('groups/mgroup1/matches/550').delete());
  });

  it('lehnt ein manipuliertes Match-Dokument ab, selbst mit plausiblen Werten', async () => {
    const db = testEnv.authenticatedContext('bob').firestore();
    await assertFails(
      db.doc('groups/mgroup1/matches/550').set({
        movie_id: 550,
        member_uids: ['bob'],
        matched_at: now(),
      }),
    );
  });

  it('lehnt das Lesen von Matches einer fremden Gruppe ab', async () => {
    const db = testEnv.authenticatedContext('carol').firestore();
    await assertFails(db.collection('groups/mgroup1/matches').get());
  });
});
