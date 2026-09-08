import assert from 'node:assert/strict';
import { before, describe, it } from 'node:test';
import admin from 'firebase-admin';
import { resolveOnePoll, resolveDuePolls } from '../moviePollEngine.js';

// Testet die reine Auswertungslogik einer Filmabend-Abstimmung (§21) direkt
// gegen den echten Firestore-Emulator (Admin-SDK, umgeht Rules - exakt wie
// `evaluateMatch` in matchEngine.test.mjs). Es gibt keinen sinnvollen Weg,
// eine Scheduled Cloud Function über einen normalen Firestore-Write "warten
// zu lassen" (sie ist zeitgesteuert, kein Dokument-Trigger) - deshalb wird
// hier die exportierte Logik, die die echte `resolveMoviePolls`-Function in
// index.js 1:1 aufruft, direkt geprüft. Das deckt die eigentliche, fachliche
// Auswertung vollständig ab; der Scheduler-Wrapper selbst enthält keine
// eigene Logik.

const PROJECT_ID = process.env.GCLOUD_PROJECT || 'film2watch-rules-test';

let db;

before(() => {
  if (admin.apps.length === 0) {
    admin.initializeApp({ projectId: PROJECT_ID });
  }
  db = admin.firestore();
});

const now = () => new Date();
const inPast = (ms = 60 * 1000) => new Date(Date.now() - ms);
const inFuture = (ms = 60 * 60 * 1000) => new Date(Date.now() + ms);

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

async function createPoll(groupId, pollId, { createdBy = 'alice', deadline = inPast(), status = 'open' } = {}) {
  const pollRef = db.doc(`groups/${groupId}/movie_night_polls/${pollId}`);
  await pollRef.set({ created_by: createdBy, created_at: now(), deadline, status });
  return pollRef;
}

async function addOption(pollRef, optionId, { scheduledAt, platformId = 8, movieId } = {}) {
  await pollRef.collection('options').doc(optionId).set({
    scheduled_at: scheduledAt,
    platform_id: platformId,
    ...(movieId !== undefined ? { movie_id: movieId } : {}),
  });
}

async function addVote(pollRef, uid, optionId) {
  await pollRef.collection('votes').doc(`${uid}_${optionId}`).set({
    uid,
    option_id: optionId,
    voted_at: now(),
  });
}

async function movieNights(groupId) {
  const snapshot = await db.collection(`groups/${groupId}/movie_nights`).get();
  return snapshot.docs;
}

describe('resolveOnePoll (§21: "Filmabend-Abstimmung", Auswertung)', () => {
  it('bestimmt die Option mit den meisten Stimmen als Gewinner', async () => {
    const groupId = `pollgroup-winner-${Date.now()}`;
    await createGroup(groupId, ['alice', 'bob', 'carol']);
    const pollRef = await createPoll(groupId, 'p1');
    await addOption(pollRef, 'opt1', { scheduledAt: inFuture(1000) });
    await addOption(pollRef, 'opt2', { scheduledAt: inFuture(2000) });
    await addVote(pollRef, 'alice', 'opt1');
    await addVote(pollRef, 'bob', 'opt2');
    await addVote(pollRef, 'carol', 'opt2');

    const result = await resolveOnePoll({ firestore: db, pollRef });

    assert.equal(result.closed, true);
    assert.equal(result.winningOptionId, 'opt2');
    const poll = await pollRef.get();
    assert.equal(poll.data().status, 'closed');
    assert.equal(poll.data().winning_option_id, 'opt2');
  });

  it('bei Gleichstand gewinnt deterministisch der früheste Termin', async () => {
    const groupId = `pollgroup-tie-${Date.now()}`;
    await createGroup(groupId, ['alice', 'bob']);
    const pollRef = await createPoll(groupId, 'p1');
    await addOption(pollRef, 'late', { scheduledAt: inFuture(2 * 24 * 60 * 60 * 1000) });
    await addOption(pollRef, 'early', { scheduledAt: inFuture(1 * 24 * 60 * 60 * 1000) });
    await addVote(pollRef, 'alice', 'late');
    await addVote(pollRef, 'bob', 'early');

    const result = await resolveOnePoll({ firestore: db, pollRef });

    assert.equal(result.winningOptionId, 'early');
  });

  it('legt für den Gewinner automatisch einen movie_nights-Eintrag an (§12-Datenvertrag)', async () => {
    const groupId = `pollgroup-mn-${Date.now()}`;
    await createGroup(groupId, ['alice', 'bob']);
    const pollRef = await createPoll(groupId, 'p1', { createdBy: 'alice' });
    const scheduledAt = inFuture(24 * 60 * 60 * 1000);
    await addOption(pollRef, 'opt1', { scheduledAt, platformId: 9, movieId: 550 });
    await addVote(pollRef, 'bob', 'opt1');

    const result = await resolveOnePoll({ firestore: db, pollRef });

    assert.ok(result.resultMovieNightId);
    const nights = await movieNights(groupId);
    assert.equal(nights.length, 1);
    const night = nights[0].data();
    assert.equal(night.created_by, 'alice');
    assert.equal(night.platform_id, 9);
    assert.equal(night.movie_id, 550);
    assert.ok(night.scheduled_at);
    const poll = await pollRef.get();
    assert.equal(poll.data().result_movie_night_id, nights[0].id);
  });

  it('ohne movie_id am Gewinner wird kein movie_id auf dem movie_nights-Eintrag gesetzt', async () => {
    const groupId = `pollgroup-nomovie-${Date.now()}`;
    await createGroup(groupId, ['alice', 'bob']);
    const pollRef = await createPoll(groupId, 'p1', { createdBy: 'alice' });
    await addOption(pollRef, 'opt1', { scheduledAt: inFuture() });
    await addVote(pollRef, 'bob', 'opt1');

    await resolveOnePoll({ firestore: db, pollRef });

    const nights = await movieNights(groupId);
    assert.equal(nights.length, 1);
    assert.equal('movie_id' in nights[0].data(), false);
  });

  it('ohne jegliche Stimme gibt es keinen Gewinner und keinen movie_nights-Eintrag', async () => {
    const groupId = `pollgroup-novotes-${Date.now()}`;
    await createGroup(groupId, ['alice', 'bob']);
    const pollRef = await createPoll(groupId, 'p1');
    await addOption(pollRef, 'opt1', { scheduledAt: inFuture() });
    await addOption(pollRef, 'opt2', { scheduledAt: inFuture(2000) });

    const result = await resolveOnePoll({ firestore: db, pollRef });

    assert.equal(result.closed, true);
    assert.equal(result.winningOptionId, null);
    assert.equal(result.resultMovieNightId, null);
    assert.equal((await movieNights(groupId)).length, 0);
    const poll = await pollRef.get();
    assert.equal(poll.data().status, 'closed');
    assert.equal(poll.data().winning_option_id, null);
  });

  it('ist idempotent: ein zweiter Aufruf für dieselbe, bereits geschlossene Abstimmung erzeugt keinen zweiten movie_nights-Eintrag', async () => {
    const groupId = `pollgroup-idem-${Date.now()}`;
    await createGroup(groupId, ['alice', 'bob']);
    const pollRef = await createPoll(groupId, 'p1', { createdBy: 'alice' });
    await addOption(pollRef, 'opt1', { scheduledAt: inFuture() });
    await addVote(pollRef, 'bob', 'opt1');

    const first = await resolveOnePoll({ firestore: db, pollRef });
    const second = await resolveOnePoll({ firestore: db, pollRef });

    assert.equal(first.closed, true);
    assert.equal(second.closed, false);
    assert.equal((await movieNights(groupId)).length, 1);
    const poll = await pollRef.get();
    assert.equal(poll.data().result_movie_night_id, first.resultMovieNightId);
  });
});

describe('resolveDuePolls (Scheduled Cloud Function `resolveMoviePolls`)', () => {
  it('wertet nur Abstimmungen aus, deren Deadline bereits erreicht ist', async () => {
    const groupId = `pollgroup-due-${Date.now()}`;
    await createGroup(groupId, ['alice', 'bob']);
    const duePoll = await createPoll(groupId, 'due', { deadline: inPast() });
    await addOption(duePoll, 'opt1', { scheduledAt: inFuture() });
    const futurePoll = await createPoll(groupId, 'future', { deadline: inFuture(60 * 60 * 1000) });
    await addOption(futurePoll, 'opt1', { scheduledAt: inFuture() });

    await resolveDuePolls({ firestore: db, now: new Date() });

    const dueSnap = await duePoll.get();
    const futureSnap = await futurePoll.get();
    assert.equal(dueSnap.data().status, 'closed');
    assert.equal(futureSnap.data().status, 'open');
  });

  it('lässt eine bereits geschlossene Abstimmung unverändert (keine erneute Auswertung)', async () => {
    const groupId = `pollgroup-alreadyclosed-${Date.now()}`;
    await createGroup(groupId, ['alice', 'bob']);
    const pollRef = await createPoll(groupId, 'p1', { deadline: inPast(), status: 'closed' });
    await pollRef.update({ winning_option_id: 'opt1', result_movie_night_id: 'mn-existing', resolved_at: now() });
    await addOption(pollRef, 'opt1', { scheduledAt: inFuture() });
    await addVote(pollRef, 'bob', 'opt1');

    await resolveDuePolls({ firestore: db, now: new Date() });

    assert.equal((await movieNights(groupId)).length, 0);
    const poll = await pollRef.get();
    assert.equal(poll.data().result_movie_night_id, 'mn-existing');
  });

  it('wertet mehrere fällige Abstimmungen über verschiedene Gruppen hinweg aus', async () => {
    const suffix = Date.now();
    const groupA = `pollgroup-multi-a-${suffix}`;
    const groupB = `pollgroup-multi-b-${suffix}`;
    await createGroup(groupA, ['alice']);
    await createGroup(groupB, ['carol']);
    const pollA = await createPoll(groupA, 'p1', { createdBy: 'alice', deadline: inPast() });
    await addOption(pollA, 'opt1', { scheduledAt: inFuture() });
    await addVote(pollA, 'alice', 'opt1');
    const pollB = await createPoll(groupB, 'p1', { createdBy: 'carol', deadline: inPast() });
    await addOption(pollB, 'opt1', { scheduledAt: inFuture() });

    await resolveDuePolls({ firestore: db, now: new Date() });

    assert.equal((await pollA.get()).data().status, 'closed');
    assert.equal((await pollB.get()).data().status, 'closed');
    assert.equal((await movieNights(groupA)).length, 1);
    assert.equal((await movieNights(groupB)).length, 0);
  });
});
