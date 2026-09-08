import assert from 'node:assert/strict';
import { before, describe, it } from 'node:test';
import admin from 'firebase-admin';
import { sendMovieNightReminder, sendDueMovieNightReminders } from '../movieNightReminderEngine.js';

// Testet die reine Reminder-Logik (§12/§21, mit dem Produktverantwortlichen
// abgestimmt: 1 Tag vor dem Termin) direkt gegen den echten
// Firestore-Emulator - analog zu `moviePollEngine.test.mjs`: es gibt keinen
// sinnvollen Weg, eine zeitgesteuerte Function über einen Firestore-Write
// "warten zu lassen", daher der direkte Aufruf der exportierten Logik, die
// die echte `sendMovieNightReminders`-Function in index.js 1:1 aufruft. Der
// tatsächliche FCM-Versand wird über einen injizierten Fake-Messaging-Client
// geprüft, exakt wie in `notifications.test.mjs`.

const PROJECT_ID = process.env.GCLOUD_PROJECT || 'film2watch-rules-test';

let db;

before(() => {
  if (admin.apps.length === 0) {
    admin.initializeApp({ projectId: PROJECT_ID });
  }
  db = admin.firestore();
});

class FakeMessaging {
  constructor() {
    this.sentMessages = [];
  }

  async sendEachForMulticast({ tokens, notification, data }) {
    this.sentMessages.push({ tokens, notification, data });
    return {
      successCount: tokens.length,
      failureCount: 0,
      responses: tokens.map(() => ({ success: true })),
    };
  }
}

const now = () => new Date();
const hoursFromNow = (hours) => new Date(Date.now() + hours * 60 * 60 * 1000);

async function createGroup(groupId, memberUids) {
  await db.doc(`groups/${groupId}`).set({
    id: groupId,
    name: 'Filmabend',
    photo_url: null,
    created_by: memberUids[0],
    created_at: now(),
    updated_at: now(),
  });
  for (const uid of memberUids) {
    await db.doc(`groups/${groupId}/members/${uid}`).set({
      uid,
      role: uid === memberUids[0] ? 'admin' : 'member',
      joined_at: now(),
    });
  }
}

async function addDevice(uid, token) {
  await db.doc(`users/${uid}/devices/${token}`).set({
    token,
    platform: 'android',
    created_at: now(),
    updated_at: now(),
  });
}

function recipientTokens(messaging) {
  return messaging.sentMessages.flatMap((m) => m.tokens);
}

async function createMovieNight(groupId, movieNightId, { scheduledAt, createdBy = 'alice' } = {}) {
  const ref = db.doc(`groups/${groupId}/movie_nights/${movieNightId}`);
  await ref.set({
    created_by: createdBy,
    created_at: now(),
    updated_at: now(),
    scheduled_at: scheduledAt,
    platform_id: 8,
  });
  return ref;
}

describe('sendMovieNightReminder', () => {
  it('sendet an alle Mitglieder inkl. des Erstellers (anders als die Erstellungs-Notification)', async () => {
    const suffix = Date.now();
    const groupId = `remindergroup-${suffix}`;
    const alice = `alice-${suffix}`;
    const bob = `bob-${suffix}`;
    await createGroup(groupId, [alice, bob]);
    await addDevice(alice, `${alice}-tok`);
    await addDevice(bob, `${bob}-tok`);
    const movieNightRef = await createMovieNight(groupId, 'mn1', { scheduledAt: hoursFromNow(20), createdBy: alice });
    const messaging = new FakeMessaging();

    const didSend = await sendMovieNightReminder({
      firestore: db,
      messaging,
      movieNightRef,
      groupId,
      scheduledAt: hoursFromNow(20),
    });

    assert.equal(didSend, true);
    assert.deepEqual(recipientTokens(messaging).sort(), [`${alice}-tok`, `${bob}-tok`].sort());
  });

  it('ein zweiter Aufruf für denselben Filmabend sendet nicht doppelt (Idempotenz)', async () => {
    const suffix = Date.now();
    const groupId = `remindergroup2-${suffix}`;
    const alice = `alice-${suffix}`;
    await createGroup(groupId, [alice]);
    await addDevice(alice, `${alice}-tok`);
    const movieNightRef = await createMovieNight(groupId, 'mn1', { scheduledAt: hoursFromNow(20), createdBy: alice });
    const messaging = new FakeMessaging();

    const first = await sendMovieNightReminder({
      firestore: db,
      messaging,
      movieNightRef,
      groupId,
      scheduledAt: hoursFromNow(20),
    });
    const second = await sendMovieNightReminder({
      firestore: db,
      messaging,
      movieNightRef,
      groupId,
      scheduledAt: hoursFromNow(20),
    });

    assert.equal(first, true);
    assert.equal(second, false);
    assert.equal(messaging.sentMessages.length, 1);
  });

  it('setzt reminder_sent_at auf dem Filmabend-Dokument', async () => {
    const suffix = Date.now();
    const groupId = `remindergroup3-${suffix}`;
    const alice = `alice-${suffix}`;
    await createGroup(groupId, [alice]);
    const movieNightRef = await createMovieNight(groupId, 'mn1', { scheduledAt: hoursFromNow(20), createdBy: alice });
    const messaging = new FakeMessaging();

    await sendMovieNightReminder({
      firestore: db,
      messaging,
      movieNightRef,
      groupId,
      scheduledAt: hoursFromNow(20),
    });

    const snapshot = await movieNightRef.get();
    assert.ok(snapshot.data().reminder_sent_at);
  });
});

describe('sendDueMovieNightReminders (Scheduled Cloud Function `sendMovieNightReminders`)', () => {
  it('sendet nur für Filmabende innerhalb der nächsten 24 Stunden', async () => {
    const suffix = Date.now();
    const groupId = `duegroup-${suffix}`;
    const alice = `alice-${suffix}`;
    await createGroup(groupId, [alice]);
    await addDevice(alice, `${alice}-tok`);
    const dueRef = await createMovieNight(groupId, 'due', { scheduledAt: hoursFromNow(20), createdBy: alice });
    const farRef = await createMovieNight(groupId, 'far', { scheduledAt: hoursFromNow(48), createdBy: alice });
    const messaging = new FakeMessaging();

    await sendDueMovieNightReminders({ firestore: db, messaging, now: now() });

    const dueSnap = await dueRef.get();
    const farSnap = await farRef.get();
    assert.ok(dueSnap.data().reminder_sent_at);
    assert.equal(farSnap.data().reminder_sent_at, undefined);
  });

  it('sendet nicht für einen bereits vergangenen Filmabend', async () => {
    const suffix = Date.now();
    const groupId = `pastgroup-${suffix}`;
    const alice = `alice-${suffix}`;
    await createGroup(groupId, [alice]);
    const pastRef = await createMovieNight(groupId, 'past', { scheduledAt: hoursFromNow(-2), createdBy: alice });
    const messaging = new FakeMessaging();

    await sendDueMovieNightReminders({ firestore: db, messaging, now: now() });

    const pastSnap = await pastRef.get();
    assert.equal(pastSnap.data().reminder_sent_at, undefined);
  });

  it('lässt einen bereits erinnerten Filmabend unangetastet (keine doppelte Benachrichtigung)', async () => {
    const suffix = Date.now();
    const groupId = `alreadygroup-${suffix}`;
    const alice = `alice-${suffix}`;
    await createGroup(groupId, [alice]);
    await addDevice(alice, `${alice}-tok`);
    const ref = await createMovieNight(groupId, 'mn1', { scheduledAt: hoursFromNow(20), createdBy: alice });
    await ref.update({ reminder_sent_at: now() });
    const messaging = new FakeMessaging();

    await sendDueMovieNightReminders({ firestore: db, messaging, now: now() });

    assert.equal(messaging.sentMessages.length, 0);
  });

  it('wertet mehrere fällige Filmabende über verschiedene Gruppen hinweg aus', async () => {
    const suffix = Date.now();
    const groupA = `multigroup-a-${suffix}`;
    const groupB = `multigroup-b-${suffix}`;
    await createGroup(groupA, ['alice']);
    await createGroup(groupB, ['carol']);
    const refA = await createMovieNight(groupA, 'mn1', { scheduledAt: hoursFromNow(10), createdBy: 'alice' });
    const refB = await createMovieNight(groupB, 'mn1', { scheduledAt: hoursFromNow(15), createdBy: 'carol' });
    const messaging = new FakeMessaging();

    const result = await sendDueMovieNightReminders({ firestore: db, messaging, now: now() });

    assert.ok((await refA.get()).data().reminder_sent_at);
    assert.ok((await refB.get()).data().reminder_sent_at);
    // >= statt ===: die Collection-Group-Query läuft projektweit, andere
    // parallel laufende Tests (z. B. moviePollEngine.test.mjs, das ebenfalls
    // movie_nights anlegt) können zusätzliche, hier nicht kontrollierte
    // Treffer beisteuern - entscheidend ist nur, dass unsere beiden
    // garantiert dabei waren.
    assert.ok(result.sent >= 2);
  });
});
