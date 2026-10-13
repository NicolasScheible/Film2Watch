import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { before, describe, it } from 'node:test';
import admin from 'firebase-admin';

// End-to-End-Test von `onSwipeWrittenForGroupIndex` (siehe index.js), das
// den dauerhaften Index `users/{uid}/swiped_groups/{groupId}` pflegt
// (PO-Entscheidung: §15 "Detaillierte Statistiken" soll auch Swipes aus
// inzwischen verlassenen Gruppen zählen, siehe README
// "Architekturentscheidung") - analog zu userGroupIndex.test.mjs, gegen den
// echten Firebase Functions Emulator + Firestore Emulator.

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
    name: 'Swipe-Index-Test',
    photo_url: null,
    created_by: createdBy,
    created_at: now(),
    updated_at: now(),
  });
}

function indexRef(uid, groupId) {
  return db.doc(`users/${uid}/swiped_groups/${groupId}`);
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

describe('onSwipeWrittenForGroupIndex (users/{uid}/swiped_groups/{groupId})', () => {
  it('legt beim ersten Swipe in einer Gruppe einen Index-Eintrag an', async () => {
    const suffix = randomUUID();
    const uid = `alice-${suffix}`;
    const groupId = `swipeindex-a-${suffix}`;
    await createGroupDoc(groupId, uid);

    await db.doc(`groups/${groupId}/swipes/${uid}_1`).set({
      uid,
      movie_id: 1,
      decision: 'like',
      created_at: now(),
      updated_at: now(),
    });

    const snap = await waitForIndexEntry(uid, groupId, true);
    assert.equal(snap.exists, true);
    assert.equal(snap.data()?.groupId, groupId);
  });

  it('bleibt bestehen, wenn der Swipe anschließend geändert wird (update)', async () => {
    const suffix = randomUUID();
    const uid = `bob-${suffix}`;
    const groupId = `swipeindex-b-${suffix}`;
    await createGroupDoc(groupId, uid);
    const ref = db.doc(`groups/${groupId}/swipes/${uid}_1`);
    await ref.set({ uid, movie_id: 1, decision: 'like', created_at: now(), updated_at: now() });
    await waitForIndexEntry(uid, groupId, true);

    await ref.update({ decision: 'dislike', updated_at: now() });

    // Feste Wartezeit statt waitForIndexEntry mit falschem Zielwert - hier
    // wird bewusst geprüft, dass sich NICHTS ändert (analog zu den anderen
    // bestehenden Trigger-Tests).
    await new Promise((resolve) => setTimeout(resolve, 3000));
    const snap = await indexRef(uid, groupId).get();
    assert.equal(snap.exists, true);
  });

  it('bleibt bestehen, wenn der (einzige) Swipe in dieser Gruppe wieder gelöscht wird (Watchlist-Entfernen)', async () => {
    const suffix = randomUUID();
    const uid = `carol-${suffix}`;
    const groupId = `swipeindex-c-${suffix}`;
    await createGroupDoc(groupId, uid);
    const ref = db.doc(`groups/${groupId}/swipes/${uid}_1`);
    await ref.set({ uid, movie_id: 1, decision: 'watchlist', created_at: now(), updated_at: now() });
    await waitForIndexEntry(uid, groupId, true);

    await ref.delete();

    await new Promise((resolve) => setTimeout(resolve, 3000));
    const snap = await indexRef(uid, groupId).get();
    assert.equal(snap.exists, true, 'der Index-Eintrag muss dauerhaft bestehen bleiben, auch ohne verbleibenden Swipe');
  });

  it('legt für mehrere Gruppen desselben Users jeweils einen eigenen Eintrag an', async () => {
    const suffix = randomUUID();
    const uid = `dave-${suffix}`;
    const groupIds = [`swipeindex-d1-${suffix}`, `swipeindex-d2-${suffix}`];

    for (const groupId of groupIds) {
      await createGroupDoc(groupId, uid);
      await db.doc(`groups/${groupId}/swipes/${uid}_1`).set({
        uid,
        movie_id: 1,
        decision: 'like',
        created_at: now(),
        updated_at: now(),
      });
    }

    for (const groupId of groupIds) {
      const snap = await waitForIndexEntry(uid, groupId, true);
      assert.equal(snap.exists, true);
    }
  });

  it('mehrere Mitglieder derselben Gruppe erhalten jeweils ihren eigenen Index-Eintrag', async () => {
    const suffix = randomUUID();
    const groupId = `swipeindex-e-${suffix}`;
    const uidOne = `erin-${suffix}`;
    const uidTwo = `frank-${suffix}`;
    await createGroupDoc(groupId, uidOne);

    await db.doc(`groups/${groupId}/swipes/${uidOne}_1`).set({
      uid: uidOne,
      movie_id: 1,
      decision: 'like',
      created_at: now(),
      updated_at: now(),
    });
    await db.doc(`groups/${groupId}/swipes/${uidTwo}_1`).set({
      uid: uidTwo,
      movie_id: 1,
      decision: 'dislike',
      created_at: now(),
      updated_at: now(),
    });

    const oneSnap = await waitForIndexEntry(uidOne, groupId, true);
    const twoSnap = await waitForIndexEntry(uidTwo, groupId, true);
    assert.equal(oneSnap.exists, true);
    assert.equal(twoSnap.exists, true);
  });
});
