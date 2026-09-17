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

    // User-Group-Index (PO-Entscheidung, Variante B): simuliert direkt das
    // Ergebnis des Cloud-Function-Triggers `onGroupMemberWritten`
    // (`functions/userGroupIndex.js`), ohne ihn selbst auszuführen - genau
    // wie `group_membership_counts` oben das Ergebnis von
    // `groupMembershipCount.js` simuliert. Diese Rules-Tests prüfen
    // ausschließlich die Zugriffsrechte auf den Index, nicht seine Pflege
    // (dafür: `functions/test/userGroupIndex.test.mjs`).
    await db.doc('users/heidi/groups/heidi-ivan-shared').set({ groupId: 'heidi-ivan-shared' });
    await db.doc('users/ivan/groups/heidi-ivan-shared').set({ groupId: 'heidi-ivan-shared' });
    await db.doc('users/ivan/groups/ivan-judy-only').set({ groupId: 'ivan-judy-only' });
    await db.doc('users/judy/groups/ivan-judy-only').set({ groupId: 'ivan-judy-only' });
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

// PO-Entscheidung (Variante B der Architektur-Analyse): "gemeinsame Gruppen"
// und die allgemeine Gruppenzugehörigkeit werden nicht mehr über eine
// `collectionGroup('members').where('uid', ...)`-Query bestimmt (siehe
// README, Abschnitt "Vorbestehender technischer Befund" - diese Query wird
// von Firestore als Query pauschal mit permission-denied abgelehnt), sondern
// über den serverseitig gepflegten Index `users/{uid}/groups/{groupId}`.
// Diese Tests prüfen exakt das dafür nötige Sicherheitsmodell: nur der
// eigene Owner darf seinen eigenen Index lesen, niemals den eines anderen
// Users, und kein Client darf den Index selbst schreiben.
describe('§4: User-Group-Index users/{uid}/groups/{groupId}', () => {
  it('erlaubt es einem User, den eigenen Index-Eintrag zu lesen', async () => {
    const db = testEnv.authenticatedContext('heidi').firestore();
    await assertSucceeds(db.doc('users/heidi/groups/heidi-ivan-shared').get());
  });

  it('verbietet es einem User, den Index-Eintrag eines anderen Users zu lesen', async () => {
    const db = testEnv.authenticatedContext('heidi').firestore();
    await assertFails(db.doc('users/ivan/groups/heidi-ivan-shared').get());
  });

  it('verbietet es einem User, über den eigenen Index-Pfad eine fremde, nicht gemeinsame Gruppe des Freundes zu lesen', async () => {
    // heidi darf ivans Index nicht lesen und kann daher strukturell nie
    // erfahren, dass "ivan-judy-only" existiert - unabhängig davon, welchen
    // Pfad sie ausprobiert.
    const db = testEnv.authenticatedContext('heidi').firestore();
    await assertFails(db.doc('users/ivan/groups/ivan-judy-only').get());
  });

  it('verbietet es dem Client, einen Index-Eintrag selbst anzulegen', async () => {
    const db = testEnv.authenticatedContext('heidi').firestore();
    await assertFails(db.doc('users/heidi/groups/faked-group').set({ groupId: 'faked-group' }));
  });

  it('verbietet es dem Client, einen Index-Eintrag selbst zu ändern', async () => {
    const db = testEnv.authenticatedContext('heidi').firestore();
    await assertFails(
      db.doc('users/heidi/groups/heidi-ivan-shared').update({ groupId: 'anders' }),
    );
  });

  it('verbietet es dem Client, einen Index-Eintrag selbst zu löschen', async () => {
    const db = testEnv.authenticatedContext('heidi').firestore();
    await assertFails(db.doc('users/heidi/groups/heidi-ivan-shared').delete());
  });

  it('lässt die bestehende members-Regel unverändert: ein Nutzer darf ein members-Dokument nur lesen, wenn er selbst Mitglied dieser Gruppe ist', async () => {
    // Regressionstest zur PO-Vorgabe "keine Änderung an der bestehenden
    // Gruppen-/Member-Rule, die deren Sicherheit abschwächt": heidi ist
    // NICHT Mitglied von "ivan-judy-only" und darf dort weiterhin nichts
    // lesen, obwohl sie über ihren eigenen Index prinzipiell weiß, dass sie
    // mit ivan in "heidi-ivan-shared" gemeinsam ist.
    const db = testEnv.authenticatedContext('heidi').firestore();
    await assertFails(db.doc('groups/ivan-judy-only/members/ivan').get());
  });

  it('erlaubt weiterhin den direkten Members-Read für die eigene, im Index bekannte Gruppe (Grundlage von watchCommonGroups)', async () => {
    // heidi ist Mitglied von "heidi-ivan-shared" (steht in ihrem eigenen
    // Index) und darf daher direkt prüfen, ob ivan dort ebenfalls Mitglied
    // ist - exakt der von GroupRepository.watchCommonGroups verwendete Weg.
    const db = testEnv.authenticatedContext('heidi').firestore();
    await assertSucceeds(db.doc('groups/heidi-ivan-shared/members/ivan').get());
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
