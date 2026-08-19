import { readFileSync } from 'node:fs';
import { after, before, describe, it } from 'node:test';
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';

// Testet die tatsächliche firestore.rules-Datei des Repos gegen den echten
// lokalen Firestore-Emulator für das Gruppen-System (Abschnitt 23 der
// Schritt-4-Anforderungen).

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
    // alice und carol sind Freunde, alice und dave nicht.
    await db.doc('friendships/alice_carol').set({ uids: ['alice', 'carol'], createdAt: now() });
  });
});

after(async () => {
  await testEnv.cleanup();
});

describe('groups/{groupId}', () => {
  it('lehnt unauthentifizierten Zugriff ab', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(db.doc('groups/g1').get());
  });

  it('erlaubt einem Mitglied das Lesen', async () => {
    const db = testEnv.authenticatedContext('bob').firestore();
    await assertSucceeds(db.doc('groups/g1').get());
  });

  it('lehnt das Lesen durch ein Nicht-Mitglied ab', async () => {
    const db = testEnv.authenticatedContext('carol').firestore();
    await assertFails(db.doc('groups/g1').get());
  });

  it('erlaubt dem Admin, die Gruppe umzubenennen', async () => {
    const db = testEnv.authenticatedContext('alice').firestore();
    await assertSucceeds(
      db.doc('groups/g1').update({ name: 'Filmabend Deluxe', updated_at: now() }),
    );
  });

  it('lehnt es ab, dass ein normales Mitglied die Gruppe verändert', async () => {
    const db = testEnv.authenticatedContext('bob').firestore();
    await assertFails(db.doc('groups/g1').update({ name: 'Gehackt', updated_at: now() }));
  });

  it('lehnt es ab, dass ein Nicht-Mitglied eine fremde Gruppe verändert', async () => {
    const db = testEnv.authenticatedContext('carol').firestore();
    await assertFails(db.doc('groups/g1').update({ name: 'Gehackt', updated_at: now() }));
  });
});

describe('groups/{groupId}/members/{uid}', () => {
  it('lehnt es ab, dass ein Fremder sich selbst als Mitglied einträgt (ohne Einladung)', async () => {
    const db = testEnv.authenticatedContext('dave').firestore();
    await assertFails(
      db.doc('groups/g1/members/dave').set({ uid: 'dave', role: 'member', joined_at: now() }),
    );
  });

  it('lehnt es ab, dass ein normales Mitglied eine fremde Rolle manipuliert', async () => {
    const db = testEnv.authenticatedContext('bob').firestore();
    await assertFails(db.doc('groups/g1/members/alice').update({ role: 'member' }));
  });
});

describe('group_invitations/{invitationId}', () => {
  it('erlaubt dem Admin, einen Freund einzuladen', async () => {
    const db = testEnv.authenticatedContext('alice').firestore();
    await assertSucceeds(
      db.doc('group_invitations/g1_carol').set({
        groupId: 'g1',
        inviterUid: 'alice',
        inviteeUid: 'carol',
        createdAt: now(),
      }),
    );
  });

  it('lehnt die Einladung eines Nicht-Freundes ab', async () => {
    const db = testEnv.authenticatedContext('alice').firestore();
    await assertFails(
      db.doc('group_invitations/g1_dave').set({
        groupId: 'g1',
        inviterUid: 'alice',
        inviteeUid: 'dave',
        createdAt: now(),
      }),
    );
  });

  it('lehnt eine doppelte Einladung an dieselbe Person ab', async () => {
    const db = testEnv.authenticatedContext('alice').firestore();
    await assertFails(
      db.doc('group_invitations/g1_carol').set({
        groupId: 'g1',
        inviterUid: 'alice',
        inviteeUid: 'carol',
        createdAt: now(),
      }),
    );
  });

  it('lehnt es ab, dass ein normales Mitglied Einladungen verschickt', async () => {
    const db = testEnv.authenticatedContext('bob').firestore();
    await assertFails(
      db.doc('group_invitations/g1_carol_bob').set({
        groupId: 'g1',
        inviterUid: 'bob',
        inviteeUid: 'carol',
        createdAt: now(),
      }),
    );
  });

  it('erlaubt der eingeladenen Person, die echte Einladung anzunehmen', async () => {
    const db = testEnv.authenticatedContext('carol').firestore();
    await assertSucceeds(
      db.doc('groups/g1/members/carol').set({ uid: 'carol', role: 'member', joined_at: now() }),
    );
  });
});
