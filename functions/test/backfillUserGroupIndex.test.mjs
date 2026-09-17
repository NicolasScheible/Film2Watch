import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { before, describe, it } from 'node:test';
import admin from 'firebase-admin';
import { backfillUserGroupIndex } from '../scripts/backfillUserGroupIndex.js';

// Testet das einmalige Backfill-Skript für den User-Group-Index (§13/§14 der
// Architektur-Entscheidung) direkt gegen den echten Firestore-Emulator.
// Simuliert den eigentlichen Backfill-Anwendungsfall (bereits bestehende
// Mitgliedschaften ohne Index-Eintrag), indem die vom Trigger
// `onGroupMemberWritten` bereits angelegten Index-Einträge vor dem Backfill
// wieder gelöscht werden - der Functions-Emulator läuft in dieser
// Testumgebung immer mit, ein "Trigger hat noch nie gelaufen"-Zustand lässt
// sich nur so nachbilden.

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
    name: 'Backfill-Test',
    photo_url: null,
    created_by: createdBy,
    created_at: now(),
    updated_at: now(),
  });
}

async function waitForIndexEntry(uid, groupId, shouldExist, { timeoutMs = 20000, intervalMs = 200 } = {}) {
  const ref = db.doc(`users/${uid}/groups/${groupId}`);
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const snap = await ref.get();
    if (snap.exists === shouldExist) return snap;
    await new Promise((resolve) => setTimeout(resolve, intervalMs));
  }
  return ref.get();
}

describe('backfillUserGroupIndex', () => {
  it('legt Index-Einträge für einen User mit einer Gruppe und einen User mit mehreren Gruppen an, nachdem diese gelöscht wurden', async () => {
    const suffix = randomUUID();
    const uidOne = `kate-${suffix}`;
    const uidMulti = `leo-${suffix}`;
    const groupSingle = `backfillgroup-single-${suffix}`;
    const groupsMulti = [`backfillgroup-m1-${suffix}`, `backfillgroup-m2-${suffix}`];

    await createGroupDoc(groupSingle, uidOne);
    await db.doc(`groups/${groupSingle}/members/${uidOne}`).set({ uid: uidOne, role: 'admin', joined_at: now() });
    await waitForIndexEntry(uidOne, groupSingle, true);

    for (const groupId of groupsMulti) {
      await createGroupDoc(groupId, uidMulti);
      await db.doc(`groups/${groupId}/members/${uidMulti}`).set({ uid: uidMulti, role: 'admin', joined_at: now() });
      await waitForIndexEntry(uidMulti, groupId, true);
    }

    // Simuliert den "Trigger ist noch nie gelaufen"-Zustand vor dem
    // eigentlichen Deployment des Fixes.
    await db.doc(`users/${uidOne}/groups/${groupSingle}`).delete();
    for (const groupId of groupsMulti) {
      await db.doc(`users/${uidMulti}/groups/${groupId}`).delete();
    }

    const result = await backfillUserGroupIndex(db);
    assert.ok(result.groupCount >= 3);
    assert.ok(result.memberCount >= 3);

    const singleSnap = await db.doc(`users/${uidOne}/groups/${groupSingle}`).get();
    assert.equal(singleSnap.exists, true);
    assert.equal(singleSnap.data()?.groupId, groupSingle);

    for (const groupId of groupsMulti) {
      const snap = await db.doc(`users/${uidMulti}/groups/${groupId}`).get();
      assert.equal(snap.exists, true);
    }
  });

  it('legt für eine Gruppe mit mehreren Mitgliedern einen Eintrag pro Mitglied an', async () => {
    const suffix = randomUUID();
    const groupId = `backfillgroup-multi-${suffix}`;
    const uidAdmin = `mona-${suffix}`;
    const uidMember = `nick-${suffix}`;
    await createGroupDoc(groupId, uidAdmin);
    await db.doc(`groups/${groupId}/members/${uidAdmin}`).set({ uid: uidAdmin, role: 'admin', joined_at: now() });
    await db.doc(`groups/${groupId}/members/${uidMember}`).set({ uid: uidMember, role: 'member', joined_at: now() });
    await waitForIndexEntry(uidAdmin, groupId, true);
    await waitForIndexEntry(uidMember, groupId, true);
    await db.doc(`users/${uidAdmin}/groups/${groupId}`).delete();
    await db.doc(`users/${uidMember}/groups/${groupId}`).delete();

    await backfillUserGroupIndex(db);

    const adminSnap = await db.doc(`users/${uidAdmin}/groups/${groupId}`).get();
    const memberSnap = await db.doc(`users/${uidMember}/groups/${groupId}`).get();
    assert.equal(adminSnap.exists, true);
    assert.equal(memberSnap.exists, true);
  });

  it('ist idempotent: ein wiederholter Lauf erzeugt keine falschen oder doppelten Daten', async () => {
    const suffix = randomUUID();
    const uid = `oscar-${suffix}`;
    const groupId = `backfillgroup-idem-${suffix}`;
    await createGroupDoc(groupId, uid);
    await db.doc(`groups/${groupId}/members/${uid}`).set({ uid, role: 'admin', joined_at: now() });
    await waitForIndexEntry(uid, groupId, true);

    await backfillUserGroupIndex(db);
    const firstRun = await db.doc(`users/${uid}/groups/${groupId}`).get();
    await backfillUserGroupIndex(db);
    const secondRun = await db.doc(`users/${uid}/groups/${groupId}`).get();

    assert.equal(firstRun.exists, true);
    assert.equal(secondRun.exists, true);
    assert.deepEqual(firstRun.data(), secondRun.data());
  });

  it('erzeugt für einen User ohne Gruppen keinen Fehler und keinen Index-Eintrag', async () => {
    const suffix = randomUUID();
    const uidWithoutGroups = `paula-${suffix}`;

    await backfillUserGroupIndex(db);

    const snapshot = await db.collection(`users/${uidWithoutGroups}/groups`).get();
    assert.equal(snapshot.size, 0);
  });
});
