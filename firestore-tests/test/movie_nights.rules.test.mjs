import { readFileSync } from 'node:fs';
import { after, before, describe, it } from 'node:test';
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';
import firebase from 'firebase/compat/app';
import 'firebase/compat/firestore';

// Testet die tatsächliche firestore.rules-Datei des Repos gegen den echten
// lokalen Firestore-Emulator für geplante Filmabende (§12: "Filmabend
// planen"). Kein Voting/RSVP (§21 bleibt ausdrücklich zurückgestellt) - nur
// Anlegen/Bearbeiten/Absagen eines einzelnen Terminvorschlags.
//
// `created_at`/`updated_at` müssen laut Rules exakt `request.time` sein -
// dafür MUSS `FieldValue.serverTimestamp()` verwendet werden (ein simples
// `new Date()` ist eine Client-Zeit und wird von den Rules zu Recht
// abgelehnt), analog zu `messages.rules.test.mjs`.
const serverTimestamp = () => firebase.firestore.FieldValue.serverTimestamp();

let testEnv;
const now = () => new Date();

function validMovieNight(overrides = {}) {
  return {
    created_by: 'alice',
    created_at: serverTimestamp(),
    updated_at: serverTimestamp(),
    scheduled_at: now(),
    platform_id: 8,
    ...overrides,
  };
}

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
    await db.doc('groups/mngroup1').set({
      id: 'mngroup1',
      name: 'Filmabend',
      photo_url: null,
      created_by: 'alice',
      created_at: now(),
      updated_at: now(),
    });
    await db.doc('groups/mngroup1/members/alice').set({ uid: 'alice', role: 'admin', joined_at: now() });
    await db.doc('groups/mngroup1/members/bob').set({ uid: 'bob', role: 'member', joined_at: now() });
    await db.doc('groups/mngroup1/members/carol_member').set({
      uid: 'carol_member',
      role: 'member',
      joined_at: now(),
    });
    // dave ist kein Mitglied von mngroup1.

    // Bestehendes Match dieser Gruppe (simuliert das Ergebnis der Cloud
    // Function, ohne sie hier auszuführen) - Grundlage für die
    // movie_id-Validierung.
    await db.doc('groups/mngroup1/matches/550').set({
      movie_id: 550,
      member_uids: ['alice', 'bob'],
      matched_at: now(),
    });

    // Ein bestehender Filmabend, von bob erstellt - Grundlage für die
    // Bearbeiten-/Absagen-Berechtigungstests.
    await db.doc('groups/mngroup1/movie_nights/bobs-night').set(
      validMovieNight({ created_by: 'bob' }),
    );
  });
});

after(async () => {
  await testEnv.cleanup();
});

describe('groups/{groupId}/movie_nights/{movieNightId}', () => {
  it('lehnt unauthentifiziertes Lesen ab', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(db.collection('groups/mngroup1/movie_nights').get());
  });

  it('lehnt das Lesen durch ein Nicht-Mitglied ab', async () => {
    const db = testEnv.authenticatedContext('dave').firestore();
    await assertFails(db.doc('groups/mngroup1/movie_nights/bobs-night').get());
  });

  it('erlaubt einem Mitglied das Lesen', async () => {
    const db = testEnv.authenticatedContext('carol_member').firestore();
    await assertSucceeds(db.doc('groups/mngroup1/movie_nights/bobs-night').get());
  });

  it('erlaubt jedem Mitglied das Anlegen eines Filmabends', async () => {
    const db = testEnv.authenticatedContext('carol_member').firestore();
    await assertSucceeds(
      db.collection('groups/mngroup1/movie_nights').add(
        validMovieNight({ created_by: 'carol_member' }),
      ),
    );
  });

  it('lehnt unauthentifiziertes Anlegen ab', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(db.collection('groups/mngroup1/movie_nights').add(validMovieNight()));
  });

  it('lehnt das Anlegen durch ein Nicht-Mitglied ab', async () => {
    const db = testEnv.authenticatedContext('dave').firestore();
    await assertFails(
      db.collection('groups/mngroup1/movie_nights').add(validMovieNight({ created_by: 'dave' })),
    );
  });

  it('lehnt es ab, dass ein Mitglied einen Filmabend im Namen eines anderen Users anlegt (UID-Manipulation)', async () => {
    const db = testEnv.authenticatedContext('carol_member').firestore();
    await assertFails(
      db.collection('groups/mngroup1/movie_nights').add(validMovieNight({ created_by: 'alice' })),
    );
  });

  it('lehnt eine erfundene created_at-Zeit ab (keine Client-Zeit)', async () => {
    const db = testEnv.authenticatedContext('carol_member').firestore();
    await assertFails(
      db.collection('groups/mngroup1/movie_nights').add({
        created_by: 'carol_member',
        created_at: new Date('2020-01-01'),
        updated_at: serverTimestamp(),
        scheduled_at: now(),
        platform_id: 8,
      }),
    );
  });

  it('lehnt ein scheduled_at ab, das kein Timestamp ist', async () => {
    const db = testEnv.authenticatedContext('carol_member').firestore();
    await assertFails(
      db.collection('groups/mngroup1/movie_nights').add({
        created_by: 'carol_member',
        created_at: serverTimestamp(),
        updated_at: serverTimestamp(),
        scheduled_at: 'morgen',
        platform_id: 8,
      }),
    );
  });

  it('lehnt eine platform_id ab, die kein int ist', async () => {
    const db = testEnv.authenticatedContext('carol_member').firestore();
    await assertFails(
      db.collection('groups/mngroup1/movie_nights').add(
        validMovieNight({ created_by: 'carol_member', platform_id: 'Netflix' }),
      ),
    );
  });

  it('erlaubt movie_id, wenn sie ein bestehendes Match der Gruppe ist', async () => {
    const db = testEnv.authenticatedContext('carol_member').firestore();
    await assertSucceeds(
      db.collection('groups/mngroup1/movie_nights').add(
        validMovieNight({ created_by: 'carol_member', movie_id: 550 }),
      ),
    );
  });

  it('lehnt movie_id ab, die kein Match der Gruppe ist', async () => {
    const db = testEnv.authenticatedContext('carol_member').firestore();
    await assertFails(
      db.collection('groups/mngroup1/movie_nights').add(
        validMovieNight({ created_by: 'carol_member', movie_id: 999 }),
      ),
    );
  });

  it('erlaubt das Anlegen ganz ohne movie_id', async () => {
    const db = testEnv.authenticatedContext('carol_member').firestore();
    await assertSucceeds(
      db.collection('groups/mngroup1/movie_nights').add(
        validMovieNight({ created_by: 'carol_member' }),
      ),
    );
  });

  it('lehnt unzulässige Zusatzfelder ab', async () => {
    const db = testEnv.authenticatedContext('carol_member').firestore();
    await assertFails(
      db.collection('groups/mngroup1/movie_nights').add({
        ...validMovieNight({ created_by: 'carol_member' }),
        note: 'Popcorn nicht vergessen',
      }),
    );
  });

  it('erlaubt es dem Ersteller, den eigenen Filmabend zu bearbeiten', async () => {
    const db = testEnv.authenticatedContext('bob').firestore();
    await assertSucceeds(
      db.doc('groups/mngroup1/movie_nights/bobs-night').update({
        updated_at: serverTimestamp(),
        scheduled_at: now(),
        platform_id: 9,
      }),
    );
  });

  it('erlaubt es dem Admin, einen fremden Filmabend zu bearbeiten', async () => {
    const db = testEnv.authenticatedContext('alice').firestore();
    await assertSucceeds(
      db.doc('groups/mngroup1/movie_nights/bobs-night').update({
        updated_at: serverTimestamp(),
        scheduled_at: now(),
        platform_id: 10,
      }),
    );
  });

  it('lehnt es ab, dass ein normales, fremdes Mitglied den Filmabend eines anderen bearbeitet', async () => {
    const db = testEnv.authenticatedContext('carol_member').firestore();
    await assertFails(
      db.doc('groups/mngroup1/movie_nights/bobs-night').update({
        updated_at: serverTimestamp(),
        scheduled_at: now(),
        platform_id: 11,
      }),
    );
  });

  it('lehnt es ab, dass created_by beim Bearbeiten verändert wird', async () => {
    const db = testEnv.authenticatedContext('bob').firestore();
    await assertFails(
      db.doc('groups/mngroup1/movie_nights/bobs-night').update({
        created_by: 'carol_member',
        updated_at: serverTimestamp(),
        scheduled_at: now(),
        platform_id: 8,
      }),
    );
  });

  it('lehnt es ab, dass created_at beim Bearbeiten verändert wird', async () => {
    const db = testEnv.authenticatedContext('bob').firestore();
    await assertFails(
      db.doc('groups/mngroup1/movie_nights/bobs-night').update({
        created_at: new Date('1999-01-01'),
        updated_at: serverTimestamp(),
        scheduled_at: now(),
        platform_id: 8,
      }),
    );
  });

  it('lehnt es ab, dass updated_at beim Bearbeiten mit einer erfundenen Zeit gesetzt wird', async () => {
    const db = testEnv.authenticatedContext('bob').firestore();
    await assertFails(
      db.doc('groups/mngroup1/movie_nights/bobs-night').update({
        updated_at: new Date('2020-01-01'),
        scheduled_at: now(),
        platform_id: 8,
      }),
    );
  });

  it('erlaubt es dem Ersteller, den eigenen Filmabend abzusagen (löschen)', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().doc('groups/mngroup1/movie_nights/to-cancel-1').set(
        validMovieNight({ created_by: 'bob' }),
      );
    });
    const db = testEnv.authenticatedContext('bob').firestore();
    await assertSucceeds(db.doc('groups/mngroup1/movie_nights/to-cancel-1').delete());
  });

  it('erlaubt es dem Admin, einen fremden Filmabend abzusagen (löschen)', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().doc('groups/mngroup1/movie_nights/to-cancel-2').set(
        validMovieNight({ created_by: 'bob' }),
      );
    });
    const db = testEnv.authenticatedContext('alice').firestore();
    await assertSucceeds(db.doc('groups/mngroup1/movie_nights/to-cancel-2').delete());
  });

  it('lehnt es ab, dass ein normales, fremdes Mitglied einen Filmabend absagt (löscht)', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().doc('groups/mngroup1/movie_nights/to-cancel-3').set(
        validMovieNight({ created_by: 'bob' }),
      );
    });
    const db = testEnv.authenticatedContext('carol_member').firestore();
    await assertFails(db.doc('groups/mngroup1/movie_nights/to-cancel-3').delete());
  });

  it('lehnt unauthentifiziertes Absagen (Löschen) ab', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().doc('groups/mngroup1/movie_nights/to-cancel-4').set(
        validMovieNight({ created_by: 'bob' }),
      );
    });
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(db.doc('groups/mngroup1/movie_nights/to-cancel-4').delete());
  });

  it('lehnt es ab, dass ein Nicht-Mitglied einen Filmabend absagt (löscht)', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().doc('groups/mngroup1/movie_nights/to-cancel-5').set(
        validMovieNight({ created_by: 'bob' }),
      );
    });
    const db = testEnv.authenticatedContext('dave').firestore();
    await assertFails(db.doc('groups/mngroup1/movie_nights/to-cancel-5').delete());
  });
});
