import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { before, describe, it } from 'node:test';
import admin from 'firebase-admin';

// End-to-End-Test der Erweiterung von `onGroupMemberWritten` (siehe
// index.js) um die Pflege von `users/{uid}/groups/{groupId}`
// (`userGroupIndex.js`) - analog zu `groupMembershipCount.test.mjs`, gegen
// den echten Firebase Functions Emulator + Firestore Emulator. PO-
// Entscheidung: der Index ersetzt die zuvor genutzte, unter echten Rules
// nicht funktionsfähige `collectionGroup('members').where('uid', ...)`-Query
// (siehe README, "Architekturentscheidung").

const PROJECT_ID = process.env.GCLOUD_PROJECT || 'film2watch-rules-test';

let db;

before(() => {
  if (admin.apps.length === 0) {
    admin.initializeApp({ projectId: PROJECT_ID });
  }
  db = admin.firestore();
});

const now = () => new Date();

async function createGroupDoc(groupId, createdBy) {
  await db.doc(`groups/${groupId}`).set({
    id: groupId,
    name: 'Index-Test',
    photo_url: null,
    created_by: createdBy,
    created_at: now(),
    updated_at: now(),
  });
}

function indexRef(uid, groupId) {
  return db.doc(`users/${uid}/groups/${groupId}`);
}

async function waitForIndexEntry(uid, groupId, shouldExist, { timeoutMs = 20000, intervalMs = 200 } = {}) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const snap = await indexRef(uid, groupId).get();
    if (snap.exists === shouldExist) return snap;
    await new Promise((resolve) => setTimeout(resolve, intervalMs));
  }
  return indexRef(uid, groupId).get();
}

describe('onGroupMemberWritten (User-Group-Index users/{uid}/groups/{groupId})', () => {
  it('A) legt den Index-Eintrag beim Anlegen einer Mitgliedschaft an', async () => {
    const suffix = randomUUID();
    const uid = `alice-${suffix}`;
    const groupId = `indexgroup-a-${suffix}`;
    await createGroupDoc(groupId, uid);

    await db.doc(`groups/${groupId}/members/${uid}`).set({ uid, role: 'admin', joined_at: now() });

    const snap = await waitForIndexEntry(uid, groupId, true);
    assert.equal(snap.exists, true);
    assert.equal(snap.data()?.groupId, groupId);
  });

  it('B) entfernt den Index-Eintrag beim Löschen einer Mitgliedschaft (Gruppe verlassen)', async () => {
    const suffix = randomUUID();
    const uid = `bob-${suffix}`;
    const groupId = `indexgroup-b-${suffix}`;
    await createGroupDoc(groupId, uid);
    const memberRef = db.doc(`groups/${groupId}/members/${uid}`);
    await memberRef.set({ uid, role: 'admin', joined_at: now() });
    await waitForIndexEntry(uid, groupId, true);

    await memberRef.delete();

    const snap = await waitForIndexEntry(uid, groupId, false);
    assert.equal(snap.exists, false);
  });

  it('C) mehrere Mitglieder einer Gruppe erhalten jeweils ihren eigenen Index-Eintrag', async () => {
    const suffix = randomUUID();
    const groupId = `indexgroup-c-${suffix}`;
    const uidAdmin = `carol-${suffix}`;
    const uidMember = `dave-${suffix}`;
    await createGroupDoc(groupId, uidAdmin);

    await db.doc(`groups/${groupId}/members/${uidAdmin}`).set({ uid: uidAdmin, role: 'admin', joined_at: now() });
    await db.doc(`groups/${groupId}/members/${uidMember}`).set({ uid: uidMember, role: 'member', joined_at: now() });

    const adminSnap = await waitForIndexEntry(uidAdmin, groupId, true);
    const memberSnap = await waitForIndexEntry(uidMember, groupId, true);
    assert.equal(adminSnap.exists, true);
    assert.equal(memberSnap.exists, true);
  });

  it('D) ein User mit mehreren Gruppen erhält einen Eintrag für jede Gruppe', async () => {
    const suffix = randomUUID();
    const uid = `erin-${suffix}`;
    const groupIds = [`indexgroup-d1-${suffix}`, `indexgroup-d2-${suffix}`, `indexgroup-d3-${suffix}`];

    for (const groupId of groupIds) {
      await createGroupDoc(groupId, uid);
      await db.doc(`groups/${groupId}/members/${uid}`).set({ uid, role: 'admin', joined_at: now() });
    }

    for (const groupId of groupIds) {
      const snap = await waitForIndexEntry(uid, groupId, true);
      assert.equal(snap.exists, true);
    }
  });

  it('E) beim Löschen einer Gruppe (alle Mitgliedschaften entfernt) verschwinden alle zugehörigen Index-Einträge', async () => {
    const suffix = randomUUID();
    const groupId = `indexgroup-e-${suffix}`;
    const uidAdmin = `frank-${suffix}`;
    const uidMember1 = `gina-${suffix}`;
    const uidMember2 = `heidi-${suffix}`;
    await createGroupDoc(groupId, uidAdmin);

    await db.doc(`groups/${groupId}/members/${uidAdmin}`).set({ uid: uidAdmin, role: 'admin', joined_at: now() });
    await db.doc(`groups/${groupId}/members/${uidMember1}`).set({ uid: uidMember1, role: 'member', joined_at: now() });
    await db.doc(`groups/${groupId}/members/${uidMember2}`).set({ uid: uidMember2, role: 'member', joined_at: now() });
    await waitForIndexEntry(uidAdmin, groupId, true);
    await waitForIndexEntry(uidMember1, groupId, true);
    await waitForIndexEntry(uidMember2, groupId, true);

    // Simuliert exakt das Verhalten von GroupRepository.deleteGroup: alle
    // Mitgliedschaften werden als Batch gelöscht, danach die Gruppe selbst.
    const batch = db.batch();
    batch.delete(db.doc(`groups/${groupId}/members/${uidAdmin}`));
    batch.delete(db.doc(`groups/${groupId}/members/${uidMember1}`));
    batch.delete(db.doc(`groups/${groupId}/members/${uidMember2}`));
    batch.delete(db.doc(`groups/${groupId}`));
    await batch.commit();

    const adminSnap = await waitForIndexEntry(uidAdmin, groupId, false);
    const member1Snap = await waitForIndexEntry(uidMember1, groupId, false);
    const member2Snap = await waitForIndexEntry(uidMember2, groupId, false);
    assert.equal(adminSnap.exists, false);
    assert.equal(member1Snap.exists, false);
    assert.equal(member2Snap.exists, false);
  });

  it('G) eine reine Rollenänderung (kein Anlegen/Löschen) verändert den Index-Eintrag nicht', async () => {
    const suffix = randomUUID();
    const uid = `ivan-${suffix}`;
    const groupId = `indexgroup-g-${suffix}`;
    await createGroupDoc(groupId, uid);
    const memberRef = db.doc(`groups/${groupId}/members/${uid}`);
    await memberRef.set({ uid, role: 'admin', joined_at: now() });
    await waitForIndexEntry(uid, groupId, true);

    await memberRef.update({ role: 'member' });

    // Feste Wartezeit statt waitForIndexEntry mit falschem Zielwert - hier
    // wird bewusst geprüft, dass sich NICHTS ändert (analog zu
    // groupMembershipCount.test.mjs).
    await new Promise((resolve) => setTimeout(resolve, 3000));
    const snap = await indexRef(uid, groupId).get();
    assert.equal(snap.exists, true);
    assert.equal(snap.data()?.groupId, groupId);
  });

  it('G) ein erneutes identisches Anlegen (z. B. durch ein wiederholtes Backfill) erzeugt keinen doppelten/falschen Zustand', async () => {
    const suffix = randomUUID();
    const uid = `judy-${suffix}`;
    const groupId = `indexgroup-g2-${suffix}`;
    await createGroupDoc(groupId, uid);
    await db.doc(`groups/${groupId}/members/${uid}`).set({ uid, role: 'admin', joined_at: now() });
    await waitForIndexEntry(uid, groupId, true);

    // Erneutes, idempotentes Anlegen desselben Index-Eintrags (wie es das
    // Backfill-Skript tun würde) darf den bestehenden Zustand nicht
    // verändern.
    await indexRef(uid, groupId).set({ groupId });

    const snap = await indexRef(uid, groupId).get();
    assert.equal(snap.exists, true);
    assert.equal(snap.data()?.groupId, groupId);
  });
});
