import { readFileSync } from 'node:fs';
import { after, before, describe, it } from 'node:test';
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';

// Testet die tatsächliche firestore.rules-Datei des Repos gegen den echten
// lokalen Firestore-Emulator für die Gruppen-Swipe-Funktion (Schritt 6).

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
    await db.doc('groups/g1').set({
      id: 'g1',
      name: 'Filmabend',
      photo_url: null,
      created_by: 'alice',
      created_at: now(),
      updated_at: now(),
    });
    await db.doc('groups/g1/members/alice').set({ uid: 'alice', role: 'admin', joined_at: now() });
    await db.doc('groups/g1/members/bob').set({ uid: 'bob', role: 'member', joined_at: now() });
    // carol ist kein Mitglied von g1.
    await db.doc('groups/g1/swipes/alice_100').set({
      uid: 'alice',
      movie_id: 100,
      decision: 'like',
      created_at: now(),
      updated_at: now(),
    });
    await db.doc('groups/g1/swipes/bob_200').set({
      uid: 'bob',
      movie_id: 200,
      decision: 'dislike',
      created_at: now(),
      updated_at: now(),
    });
  });
});

after(async () => {
  await testEnv.cleanup();
});

describe('groups/{groupId}/swipes/{swipeId}', () => {
  it('lehnt unauthentifiziertes Lesen ab', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(db.doc('groups/g1/swipes/alice_100').get());
  });

  it('lehnt unauthentifiziertes Schreiben ab', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(
      db.doc('groups/g1/swipes/alice_999').set({
        uid: 'alice',
        movie_id: 999,
        decision: 'like',
        created_at: now(),
        updated_at: now(),
      }),
    );
  });

  it('erlaubt einem Mitglied, den eigenen Swipe anzulegen (like)', async () => {
    const db = testEnv.authenticatedContext('bob').firestore();
    await assertSucceeds(
      db.doc('groups/g1/swipes/bob_300').set({
        uid: 'bob',
        movie_id: 300,
        decision: 'like',
        created_at: now(),
        updated_at: now(),
      }),
    );
  });

  it('erlaubt einem Mitglied, den eigenen Swipe anzulegen (dislike)', async () => {
    const db = testEnv.authenticatedContext('bob').firestore();
    await assertSucceeds(
      db.doc('groups/g1/swipes/bob_301').set({
        uid: 'bob',
        movie_id: 301,
        decision: 'dislike',
        created_at: now(),
        updated_at: now(),
      }),
    );
  });

  it('erlaubt einem Mitglied das Lesen eines Swipes in der eigenen Gruppe', async () => {
    const db = testEnv.authenticatedContext('bob').firestore();
    await assertSucceeds(db.doc('groups/g1/swipes/alice_100').get());
  });

  it('lehnt es ab, dass ein Mitglied den Swipe eines anderen Mitglieds anlegt', async () => {
    const db = testEnv.authenticatedContext('bob').firestore();
    await assertFails(
      db.doc('groups/g1/swipes/alice_400').set({
        uid: 'alice',
        movie_id: 400,
        decision: 'like',
        created_at: now(),
        updated_at: now(),
      }),
    );
  });

  it('lehnt das Lesen durch ein Nicht-Mitglied ab', async () => {
    const db = testEnv.authenticatedContext('carol').firestore();
    await assertFails(db.doc('groups/g1/swipes/alice_100').get());
  });

  it('lehnt das Schreiben durch ein Nicht-Mitglied ab', async () => {
    const db = testEnv.authenticatedContext('carol').firestore();
    await assertFails(
      db.doc('groups/g1/swipes/carol_500').set({
        uid: 'carol',
        movie_id: 500,
        decision: 'like',
        created_at: now(),
        updated_at: now(),
      }),
    );
  });

  it('lehnt es ab, dass User A den Swipe von User B löscht', async () => {
    const db = testEnv.authenticatedContext('alice').firestore();
    await assertFails(db.doc('groups/g1/swipes/bob_200').delete());
  });

  it('lehnt es ab, dass der eigene Swipe gelöscht wird (kein Löschen in diesem Schritt)', async () => {
    const db = testEnv.authenticatedContext('bob').firestore();
    await assertFails(db.doc('groups/g1/swipes/bob_200').delete());
  });

  it('erlaubt es dem User, den eigenen Swipe zu aktualisieren (Like -> Dislike)', async () => {
    const db = testEnv.authenticatedContext('alice').firestore();
    await assertSucceeds(
      db.doc('groups/g1/swipes/alice_100').update({ decision: 'dislike', updated_at: now() }),
    );
  });

  it('lehnt es ab, dass beim Update uid oder movie_id verändert werden', async () => {
    const db = testEnv.authenticatedContext('bob').firestore();
    await assertFails(
      db.doc('groups/g1/swipes/bob_200').update({ movie_id: 999, updated_at: now() }),
    );
  });

  it('lehnt eine ungültige decision beim Anlegen ab', async () => {
    const db = testEnv.authenticatedContext('bob').firestore();
    await assertFails(
      db.doc('groups/g1/swipes/bob_600').set({
        uid: 'bob',
        movie_id: 600,
        decision: 'maybe',
        created_at: now(),
        updated_at: now(),
      }),
    );
  });

  it('lehnt eine Dokument-ID ab, die nicht dem Muster {uid}_{movieId} entspricht', async () => {
    const db = testEnv.authenticatedContext('bob').firestore();
    await assertFails(
      db.doc('groups/g1/swipes/wrong_id').set({
        uid: 'bob',
        movie_id: 700,
        decision: 'like',
        created_at: now(),
        updated_at: now(),
      }),
    );
  });
});
