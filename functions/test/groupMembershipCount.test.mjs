import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { before, describe, it } from 'node:test';
import admin from 'firebase-admin';

// End-to-End-Test der echten Cloud Function `onGroupMemberWritten` (siehe
// index.js) gegen den echten Firebase Functions Emulator + Firestore
// Emulator - analog zu `matchEngine.test.mjs`. Es wird bewusst NICHT nur die
// reine `applyMembershipCountDelta`-Funktion direkt aufgerufen, sondern über
// echte Firestore-Writes der komplette Trigger-Pfad durchlaufen (§15:
// Free-Gruppen-Limit von 3, unbegrenzt für Premium).
//
// WICHTIG: anders als bei den übrigen End-to-End-Tests (matchEngine,
// notifications, moviePollEngine, ...), die alle NUR innerhalb einer per
// `Date.now()` eindeutigen groupId prüfen, liest dieser Test
// `group_membership_counts/{uid}` - einen Zähler, der GLOBAL (gruppen-
// übergreifend) pro uid geführt wird. Ein per `Date.now()` gebildeter uid
// (Millisekunden-Auflösung) kann daher mit einem gleichnamigen uid aus einem
// ANDEREN, gleichzeitig laufenden Test-File kollidieren (`node --test` führt
// mehrere *.test.mjs-Dateien parallel aus) und den erwarteten exakten
// Zählerwert verfälschen - deshalb hier zusätzlich `randomUUID()` statt nur
// eines Zeitstempels.

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
    name: 'Limit-Test',
    photo_url: null,
    created_by: createdBy,
    created_at: now(),
    updated_at: now(),
  });
}

function countRef(uid) {
  return db.doc(`group_membership_counts/${uid}`);
}

/**
 * Wartet, bis der (asynchrone) Zähler den erwarteten Wert erreicht hat.
 * Bewusst großzügigerer Standard-Timeout als bei `waitForMatch`/
 * `waitForPreferences` (10000ms): im Test isoliert lief jeder Fall zuverlässig
 * in unter 5s durch, aber innerhalb der VOLLEN Test-Suite (alle *.test.mjs-
 * Dateien parallel, einziger, gemeinsamer Functions-Emulator-Prozess
 * verarbeitet Trigger sequenziell) reichte 10000ms nicht immer - derselbe,
 * bereits an anderer Stelle dokumentierte Effekt, dass mehr gleichzeitig
 * laufende Functions/Tests das Trigger-Dispatch spürbar verlangsamen
 * (`assertNoMatchAfterSettling` in `matchEngine.test.mjs`).
 */
async function waitForCount(uid, expected, { timeoutMs = 20000, intervalMs = 200 } = {}) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const snap = await countRef(uid).get();
    if (snap.exists && snap.data().count === expected) return snap;
    await new Promise((resolve) => setTimeout(resolve, intervalMs));
  }
  return countRef(uid).get();
}

describe('onGroupMemberWritten (§15-Gruppen-Limit-Zähler)', () => {
  it('erhöht den Zähler beim Anlegen einer Mitgliedschaft', async () => {
    const suffix = Date.now();
    const uid = `alice-${randomUUID()}`;
    const groupId = `countgroup-${suffix}`;
    await createGroupDoc(groupId, uid);

    await db.doc(`groups/${groupId}/members/${uid}`).set({ uid, role: 'admin', joined_at: now() });

    const snap = await waitForCount(uid, 1);
    assert.equal(snap.data()?.count, 1);
  });

  it('verringert den Zähler beim Löschen einer Mitgliedschaft (Gruppe verlassen)', async () => {
    const suffix = Date.now();
    const uid = `bob-${randomUUID()}`;
    const groupId = `countgroup2-${suffix}`;
    await createGroupDoc(groupId, uid);
    const memberRef = db.doc(`groups/${groupId}/members/${uid}`);
    await memberRef.set({ uid, role: 'admin', joined_at: now() });
    await waitForCount(uid, 1);

    await memberRef.delete();

    const snap = await waitForCount(uid, 0);
    assert.equal(snap.data()?.count, 0);
  });

  it('zählt mehrere Gruppen desselben Users korrekt hoch', async () => {
    const suffix = Date.now();
    const uid = `carol-${randomUUID()}`;
    for (let i = 0; i < 3; i++) {
      const groupId = `countgroup3-${suffix}-${i}`;
      await createGroupDoc(groupId, uid);
      await db.doc(`groups/${groupId}/members/${uid}`).set({ uid, role: 'admin', joined_at: now() });
    }

    const snap = await waitForCount(uid, 3);
    assert.equal(snap.data()?.count, 3);
  });

  it('ändert den Zähler bei einer reinen Rollenänderung nicht (kein Anlegen/Löschen)', async () => {
    const suffix = Date.now();
    const uid = `dave-${randomUUID()}`;
    const groupId = `countgroup4-${suffix}`;
    await createGroupDoc(groupId, uid);
    const memberRef = db.doc(`groups/${groupId}/members/${uid}`);
    await memberRef.set({ uid, role: 'admin', joined_at: now() });
    await waitForCount(uid, 1);

    await memberRef.update({ role: 'member' });

    // Feste Wartezeit statt waitForCount mit einem falschen Zielwert - hier
    // wird bewusst geprüft, dass sich NICHTS ändert.
    await new Promise((resolve) => setTimeout(resolve, 3000));
    const snap = await countRef(uid).get();
    assert.equal(snap.data()?.count, 1);
  });
});
