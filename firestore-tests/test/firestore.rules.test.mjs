import { readFileSync } from 'node:fs';
import { after, before, describe, it } from 'node:test';
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';
import { setLogLevel } from 'firebase/firestore';

// Testet die tatsächliche firestore.rules-Datei des Repos gegen den echten
// lokalen Firestore-Emulator (nicht gegen ein vereinfachtes Fake, das
// exists()/resource nicht unterstützt). Deckt Abschnitt 18 der Schritt-3-
// Anforderungen ab: unauthentifizierter Zugriff, eigenes vs. fremdes Profil,
// ungültige Freundschafts-Schreibvorgänge.

setLogLevel('error');

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'film2watch-rules-test',
    firestore: {
      rules: readFileSync('../firestore.rules', 'utf8'),
      host: '127.0.0.1',
      port: 8080,
    },
  });
});

after(async () => {
  await testEnv.cleanup();
});

const now = () => new Date();

describe('users/{uid}', () => {
  it('lehnt unauthentifizierten Zugriff ab', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(db.doc('users/alice').get());
  });

  it('erlaubt dem User, sein eigenes Profil zu bearbeiten', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().doc('users/alice').set({
        uid: 'alice',
        name: 'Alice',
        email: 'alice@film2watch.app',
        profile_picture: null,
        friend_code: 'FILM-1111',
        created_at: now(),
      });
    });

    const db = testEnv.authenticatedContext('alice').firestore();
    await assertSucceeds(db.doc('users/alice').update({ name: 'Alice Neu' }));
  });

  it('verhindert, dass ein User ein fremdes Profil verändert', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().doc('users/bob').set({
        uid: 'bob',
        name: 'Bob',
        email: 'bob@film2watch.app',
        profile_picture: null,
        friend_code: 'FILM-2222',
        created_at: now(),
      });
    });

    const db = testEnv.authenticatedContext('alice').firestore();
    await assertFails(db.doc('users/bob').update({ name: 'Gehackt' }));
  });

  it('verhindert, dass der User seinen eigenen friend_code überschreibt', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().doc('users/carol').set({
        uid: 'carol',
        name: 'Carol',
        email: 'carol@film2watch.app',
        profile_picture: null,
        friend_code: 'FILM-3333',
        created_at: now(),
      });
    });

    const db = testEnv.authenticatedContext('carol').firestore();
    await assertFails(db.doc('users/carol').update({ friend_code: 'FILM-9999' }));
  });
});

describe('friend_codes/{code}', () => {
  it('lehnt unauthentifizierten Zugriff ab', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(db.doc('friend_codes/FILM-4444').get());
  });

  it('erlaubt es, den eigenen Code anzulegen', async () => {
    const db = testEnv.authenticatedContext('alice').firestore();
    await assertSucceeds(db.doc('friend_codes/FILM-4444').set({ uid: 'alice' }));
  });

  it('lehnt es ab, einen Code für einen anderen User anzulegen', async () => {
    const db = testEnv.authenticatedContext('alice').firestore();
    await assertFails(db.doc('friend_codes/FILM-5555').set({ uid: 'bob' }));
  });

  it('erlaubt jedem authentifizierten User das Nachschlagen eines fremden Codes (get)', async () => {
    const db = testEnv.authenticatedContext('bob').firestore();
    await assertSucceeds(db.doc('friend_codes/FILM-4444').get());
  });

  it('lehnt das Auflisten aller Codes ab (keine Enumeration/Scraping möglich)', async () => {
    const db = testEnv.authenticatedContext('bob').firestore();
    await assertFails(db.collection('friend_codes').get());
  });

  it('lehnt es ab, einen bestehenden Code zu ändern', async () => {
    const db = testEnv.authenticatedContext('alice').firestore();
    await assertFails(db.doc('friend_codes/FILM-4444').update({ uid: 'bob' }));
  });

  it('lehnt es ab, einen bestehenden Code zu löschen', async () => {
    const db = testEnv.authenticatedContext('alice').firestore();
    await assertFails(db.doc('friend_codes/FILM-4444').delete());
  });
});

describe('public_profiles/{userId}', () => {
  it('lehnt unauthentifizierten Zugriff ab', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(db.doc('public_profiles/alice').get());
  });

  it('erlaubt es, das eigene öffentliche Profil anzulegen', async () => {
    const db = testEnv.authenticatedContext('alice').firestore();
    await assertSucceeds(
      db.doc('public_profiles/alice').set({
        uid: 'alice',
        name: 'Alice',
        profile_picture: null,
        friend_code: 'FILM-4444',
      }),
    );
  });

  it('lehnt es ab, ein öffentliches Profil für einen anderen User anzulegen', async () => {
    const db = testEnv.authenticatedContext('alice').firestore();
    await assertFails(
      db.doc('public_profiles/bob').set({
        uid: 'bob',
        name: 'Bob',
        profile_picture: null,
        friend_code: 'FILM-5555',
      }),
    );
  });

  it('erlaubt jedem authentifizierten User das Lesen eines fremden öffentlichen Profils (get)', async () => {
    const db = testEnv.authenticatedContext('bob').firestore();
    await assertSucceeds(db.doc('public_profiles/alice').get());
  });

  it('lehnt das Auflisten aller öffentlichen Profile ab (keine Enumeration/Scraping möglich)', async () => {
    const db = testEnv.authenticatedContext('bob').firestore();
    await assertFails(db.collection('public_profiles').get());
  });

  it('erlaubt dem Owner, Name/Bild zu ändern, solange friend_code unverändert bleibt', async () => {
    const db = testEnv.authenticatedContext('alice').firestore();
    await assertSucceeds(
      db.doc('public_profiles/alice').update({ name: 'Alice Neu' }),
    );
  });

  it('lehnt es ab, dass der Owner den eigenen friend_code über das öffentliche Profil ändert', async () => {
    const db = testEnv.authenticatedContext('alice').firestore();
    await assertFails(
      db.doc('public_profiles/alice').update({ friend_code: 'FILM-9999' }),
    );
  });

  it('lehnt es ab, dass ein fremder User ein öffentliches Profil ändert', async () => {
    const db = testEnv.authenticatedContext('bob').firestore();
    await assertFails(
      db.doc('public_profiles/alice').update({ name: 'Gehackt' }),
    );
  });

  it('lehnt es ab, ein öffentliches Profil zu löschen', async () => {
    const db = testEnv.authenticatedContext('alice').firestore();
    await assertFails(db.doc('public_profiles/alice').delete());
  });
});

describe('friend_requests/{requestId}', () => {
  it('lehnt eine Anfrage ab, die nicht vom Absender selbst erstellt wird', async () => {
    const db = testEnv.authenticatedContext('alice').firestore();
    await assertFails(
      db.doc('friend_requests/bob_carol').set({
        fromUid: 'bob',
        toUid: 'carol',
        createdAt: now(),
      }),
    );
  });

  it('lehnt eine Anfrage an sich selbst ab', async () => {
    const db = testEnv.authenticatedContext('alice').firestore();
    await assertFails(
      db.doc('friend_requests/alice_alice').set({
        fromUid: 'alice',
        toUid: 'alice',
        createdAt: now(),
      }),
    );
  });

  it('erlaubt eine gültige, an sich selbst gerichtete Anfrage', async () => {
    const db = testEnv.authenticatedContext('alice').firestore();
    await assertSucceeds(
      db.doc('friend_requests/alice_bob').set({
        fromUid: 'alice',
        toUid: 'bob',
        createdAt: now(),
      }),
    );
  });

  it('lehnt eine doppelte Anfrage in dieselbe Richtung ab', async () => {
    const db = testEnv.authenticatedContext('alice').firestore();
    // Die erste Anfrage existiert bereits aus dem vorherigen Test.
    await assertFails(
      db.doc('friend_requests/alice_bob').set({
        fromUid: 'alice',
        toUid: 'bob',
        createdAt: now(),
      }),
    );
  });
});

describe('friendships/{pairId}', () => {
  it('lehnt eine Freundschaft ohne zugehörige Anfrage ab', async () => {
    const db = testEnv.authenticatedContext('dave').firestore();
    await assertFails(
      db.doc('friendships/dave_erin').set({
        uids: ['dave', 'erin'],
        createdAt: now(),
      }),
    );
  });

  it('erlaubt die Annahme einer echten, eingehenden Anfrage', async () => {
    // "bob" nimmt die Anfrage von "alice" (aus dem vorherigen Block) an.
    const db = testEnv.authenticatedContext('bob').firestore();
    await assertSucceeds(
      db.doc('friendships/alice_bob').set({
        uids: ['alice', 'bob'],
        createdAt: now(),
      }),
    );
  });

  it('lehnt eine doppelte Freundschaft für dasselbe Paar ab', async () => {
    const db = testEnv.authenticatedContext('bob').firestore();
    await assertFails(
      db.doc('friendships/alice_bob').set({
        uids: ['alice', 'bob'],
        createdAt: now(),
      }),
    );
  });

  it('lehnt eine neue Anfrage zwischen bereits bestehenden Freunden ab', async () => {
    const db = testEnv.authenticatedContext('bob').firestore();
    await assertFails(
      db.doc('friend_requests/bob_alice').set({
        fromUid: 'bob',
        toUid: 'alice',
        createdAt: now(),
      }),
    );
  });
});
