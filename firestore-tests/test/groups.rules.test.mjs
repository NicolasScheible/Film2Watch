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

    // Fixtures für das §15-Gruppen-Limit (max. 3 Gruppen für Free-User,
    // unbegrenzt für Premium) - eigene, unbenutzte User (erin/frank/gina),
    // damit diese Tests nicht mit den obigen Gruppen-Tests interferieren.
    // `group_membership_counts` simuliert hier direkt das Ergebnis des
    // Cloud-Function-Triggers `onGroupMemberWritten`, ohne ihn auszuführen -
    // die Rules selbst kennen nur den gespeicherten Zählerwert.
    await db.doc('group_membership_counts/erin').set({ count: 3 });
    await db.doc('group_membership_counts/frank').set({ count: 3 });
    await db.doc('premium_status/frank').set({ is_premium: true });
    await db.doc('group_membership_counts/gina').set({ count: 2 });

    await db.doc('groups/limit-admin-free').set({
      id: 'limit-admin-free',
      name: 'Limit-Test',
      photo_url: null,
      created_by: 'erin',
      created_at: now(),
      updated_at: now(),
    });
    await db.doc('groups/limit-admin-premium').set({
      id: 'limit-admin-premium',
      name: 'Limit-Test',
      photo_url: null,
      created_by: 'frank',
      created_at: now(),
      updated_at: now(),
    });
    await db.doc('groups/limit-admin-under').set({
      id: 'limit-admin-under',
      name: 'Limit-Test',
      photo_url: null,
      created_by: 'gina',
      created_at: now(),
      updated_at: now(),
    });
    await db.doc('groups/limit-invite-free').set({
      id: 'limit-invite-free',
      name: 'Limit-Test',
      photo_url: null,
      created_by: 'alice',
      created_at: now(),
      updated_at: now(),
    });
    await db.doc('group_invitations/limit-invite-free_erin').set({
      groupId: 'limit-invite-free',
      inviterUid: 'alice',
      inviteeUid: 'erin',
      createdAt: now(),
    });
    await db.doc('groups/limit-invite-premium').set({
      id: 'limit-invite-premium',
      name: 'Limit-Test',
      photo_url: null,
      created_by: 'alice',
      created_at: now(),
      updated_at: now(),
    });
    await db.doc('group_invitations/limit-invite-premium_frank').set({
      groupId: 'limit-invite-premium',
      inviterUid: 'alice',
      inviteeUid: 'frank',
      createdAt: now(),
    });

    // Fixtures für §4 ("gemeinsame Gruppen" im Freundes-Profil): heidi und
    // ivan haben eine gemeinsame Gruppe; ivan ist zusätzlich (ohne heidi)
    // Mitglied einer zweiten Gruppe mit judy - diese darf heidi niemals über
    // eine `members`-Collection-Group-Query nach ivans uid zu sehen bekommen.
    await db.doc('groups/heidi-ivan-shared').set({
      id: 'heidi-ivan-shared',
      name: 'Gemeinsame Gruppe',
      photo_url: null,
      created_by: 'heidi',
      created_at: now(),
      updated_at: now(),
    });
    await db.doc('groups/heidi-ivan-shared/members/heidi').set({
      uid: 'heidi',
      role: 'admin',
      joined_at: now(),
    });
    await db.doc('groups/heidi-ivan-shared/members/ivan').set({
      uid: 'ivan',
      role: 'member',
      joined_at: now(),
    });
    await db.doc('groups/ivan-judy-only').set({
      id: 'ivan-judy-only',
      name: 'Nicht gemeinsame Gruppe',
      photo_url: null,
      created_by: 'ivan',
      created_at: now(),
      updated_at: now(),
    });
    await db.doc('groups/ivan-judy-only/members/ivan').set({
      uid: 'ivan',
      role: 'admin',
      joined_at: now(),
    });
    await db.doc('groups/ivan-judy-only/members/judy').set({
      uid: 'judy',
      role: 'member',
      joined_at: now(),
    });
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

describe('§15-Gruppen-Limit: groups/{groupId}/members/{uid} create', () => {
  it('lehnt es ab, dass ein Free-User mit bereits 3 Gruppen eine weitere Gruppe anlegt', async () => {
    const db = testEnv.authenticatedContext('erin').firestore();
    await assertFails(
      db.doc('groups/limit-admin-free/members/erin').set({ uid: 'erin', role: 'admin', joined_at: now() }),
    );
  });

  it('erlaubt es einem Premium-User mit bereits 3 Gruppen, eine weitere Gruppe anzulegen', async () => {
    const db = testEnv.authenticatedContext('frank').firestore();
    await assertSucceeds(
      db.doc('groups/limit-admin-premium/members/frank').set({ uid: 'frank', role: 'admin', joined_at: now() }),
    );
  });

  it('erlaubt es einem Free-User mit erst 2 Gruppen, eine 3. Gruppe anzulegen', async () => {
    const db = testEnv.authenticatedContext('gina').firestore();
    await assertSucceeds(
      db.doc('groups/limit-admin-under/members/gina').set({ uid: 'gina', role: 'admin', joined_at: now() }),
    );
  });

  it('lehnt es ab, dass ein Free-User mit bereits 3 Gruppen eine Einladung annimmt', async () => {
    const db = testEnv.authenticatedContext('erin').firestore();
    await assertFails(
      db.doc('groups/limit-invite-free/members/erin').set({ uid: 'erin', role: 'member', joined_at: now() }),
    );
  });

  it('erlaubt es einem Premium-User mit bereits 3 Gruppen, eine Einladung anzunehmen', async () => {
    const db = testEnv.authenticatedContext('frank').firestore();
    await assertSucceeds(
      db.doc('groups/limit-invite-premium/members/frank').set({ uid: 'frank', role: 'member', joined_at: now() }),
    );
  });
});

describe('§4: gemeinsame Gruppen - Cross-User Collection-Group-Query auf members', () => {
  it('liefert bei einer Query nach der uid eines Freundes nur die tatsächlich gemeinsame Gruppe, nie dessen fremde Gruppe', async () => {
    const db = testEnv.authenticatedContext('heidi').firestore();
    const snapshot = await db.collectionGroup('members').where('uid', '==', 'ivan').get();

    const groupIds = snapshot.docs.map((doc) => doc.ref.parent.parent.id);
    if (groupIds.includes('ivan-judy-only')) {
      throw new Error(
        'heidi konnte über die members-Collection-Group-Query eine fremde Gruppe von ivan sehen (Privacy-Leck).',
      );
    }
    if (!groupIds.includes('heidi-ivan-shared')) {
      throw new Error('Die tatsächlich gemeinsame Gruppe wurde nicht gefunden.');
    }
  });

  it('liefert für einen völlig fremden User (keine gemeinsame Gruppe) keine Treffer', async () => {
    const db = testEnv.authenticatedContext('heidi').firestore();
    const snapshot = await db.collectionGroup('members').where('uid', '==', 'judy').get();

    const groupIds = snapshot.docs.map((doc) => doc.ref.parent.parent.id);
    if (groupIds.length !== 0) {
      throw new Error(`heidi hat unerwartet Treffer für judy erhalten: ${groupIds.join(', ')}`);
    }
  });
});

describe('group_membership_counts/{uid}', () => {
  it('erlaubt dem eigenen User nur das Lesen', async () => {
    const db = testEnv.authenticatedContext('erin').firestore();
    await assertSucceeds(db.doc('group_membership_counts/erin').get());
  });

  it('lehnt das Lesen eines fremden Zählers ab', async () => {
    const db = testEnv.authenticatedContext('frank').firestore();
    await assertFails(db.doc('group_membership_counts/erin').get());
  });

  it('lehnt jeden clientseitigen Schreibzugriff ab, auch auf den eigenen Zähler', async () => {
    const db = testEnv.authenticatedContext('erin').firestore();
    await assertFails(db.doc('group_membership_counts/erin').set({ count: 0 }));
  });
});
