import assert from 'node:assert/strict';
import { before, describe, it } from 'node:test';
import admin from 'firebase-admin';

// End-to-End-Test der echten Cloud Function `onSwipeWrittenForPreferences`
// (siehe index.js) gegen den echten Firebase Functions Emulator + Firestore
// Emulator - analog zu matchEngine.test.mjs, aber für die Genre-Präferenz-/
// Anti-Boost-Pflege in `user_preferences/{uid}` (§7/§18/§17.4).
//
// WICHTIG: user_preferences ist global pro User (nicht pro Gruppe) - jeder
// Test verwendet daher eine eigene, in dieser Datei sonst nirgends
// verwendete uid, damit sich die Tests nicht gegenseitig über dieselbe
// Aggregation beeinflussen.

const PROJECT_ID = process.env.GCLOUD_PROJECT || 'film2watch-rules-test';

let db;

before(() => {
  admin.initializeApp({ projectId: PROJECT_ID });
  db = admin.firestore();
});

const now = () => new Date();
const daysAgo = (days) => new Date(Date.now() - days * 24 * 60 * 60 * 1000);

async function createGroup(groupId, memberUids) {
  await db.doc(`groups/${groupId}`).set({
    id: groupId,
    name: 'Testgruppe',
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

async function setSwipe(groupId, uid, movieId, decision, { genreIds = [], createdAt } = {}) {
  const ref = db.doc(`groups/${groupId}/swipes/${uid}_${movieId}`);
  await ref.set({
    uid,
    movie_id: movieId,
    decision,
    genre_ids: genreIds,
    created_at: createdAt || now(),
    updated_at: now(),
  });
  return ref;
}

function preferencesRef(uid) {
  return db.doc(`user_preferences/${uid}`);
}

/** Wartet, bis `user_preferences/{uid}` existiert und [predicate] erfüllt. */
async function waitForPreferences(uid, predicate, { timeoutMs = 10000, intervalMs = 200 } = {}) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const snap = await preferencesRef(uid).get();
    if (snap.exists && predicate(snap.data())) return snap;
    await new Promise((resolve) => setTimeout(resolve, intervalMs));
  }
  return preferencesRef(uid).get();
}

describe('onSwipeWrittenForPreferences -> Genre-Präferenz/Anti-Boost (echter Functions-Emulator)', () => {
  it('1. ein Like trägt zur genre_affinity bei und macht das Genre zu einem Top-Genre', async () => {
    await createGroup('p1', ['genre-user-1', 'p1-other']);
    await setSwipe('p1', 'genre-user-1', 701, 'like', { genreIds: [27] });

    const snap = await waitForPreferences('genre-user-1', (data) => (data.top_genres || []).includes(27));

    assert.deepEqual(snap.data().top_genres, [27]);
    assert.ok(snap.data().genre_affinity['27'] > 0);
  });

  it('2. nur die Top-3-Genres nach Affinität landen in top_genres', async () => {
    await createGroup('p2', ['genre-user-2', 'p2-other']);
    // Genre 1: 4 Likes, Genre 2: 3, Genre 3: 2, Genre 4: 1 -> absteigende
    // Affinität in dieser Reihenfolge, Genre 4 fällt aus den Top-3 heraus.
    let movieId = 710;
    for (let i = 0; i < 4; i++) await setSwipe('p2', 'genre-user-2', movieId++, 'like', { genreIds: [1] });
    for (let i = 0; i < 3; i++) await setSwipe('p2', 'genre-user-2', movieId++, 'like', { genreIds: [2] });
    for (let i = 0; i < 2; i++) await setSwipe('p2', 'genre-user-2', movieId++, 'like', { genreIds: [3] });
    await setSwipe('p2', 'genre-user-2', movieId++, 'like', { genreIds: [4] });

    // Zehn Swipes lösen zehn einzelne Trigger-Ausführungen aus (jede mit
    // eigener collectionGroup-Query + Schreibvorgang) - deutlich mehr Arbeit
    // als bei den anderen Tests dieser Datei, daher ein großzügigeres
    // Timeout statt eines künstlich niedrigen Werts.
    const snap = await waitForPreferences(
      'genre-user-2',
      (data) => (data.top_genres || []).length === 3,
      { timeoutMs: 25000 },
    );

    assert.deepEqual(snap.data().top_genres, [1, 2, 3]);
  });

  it('3. ein Dislike erhöht disliked_genres, aber nicht genre_affinity', async () => {
    await createGroup('p3', ['genre-user-3', 'p3-other']);
    await setSwipe('p3', 'genre-user-3', 720, 'dislike', { genreIds: [99] });

    const snap = await waitForPreferences('genre-user-3', (data) => (data.disliked_genres || {})['99'] === 1);

    assert.equal(snap.data().disliked_genres['99'], 1);
    assert.equal(snap.data().genre_affinity['99'], undefined);
    assert.deepEqual(snap.data().top_genres, []);
  });

  it('4. ein über 30 Tage alter Like ist vollständig verfallen und erscheint nicht in top_genres', async () => {
    await createGroup('p4', ['genre-user-4', 'p4-other']);
    await setSwipe('p4', 'genre-user-4', 730, 'like', {
      genreIds: [55],
      createdAt: daysAgo(60),
    });
    // Ein zweiter, aktueller Like in einem anderen Genre stellt sicher, dass
    // die Function tatsächlich gelaufen ist und wir nicht nur auf ein
    // "noch nicht aktualisiert"-Dokument warten.
    await setSwipe('p4', 'genre-user-4', 731, 'like', { genreIds: [56] });

    const snap = await waitForPreferences('genre-user-4', (data) => (data.top_genres || []).includes(56));

    assert.deepEqual(snap.data().top_genres, [56]);
    assert.equal(snap.data().genre_affinity['55'] ?? 0, 0);
  });

  it('5. Löschen des einzigen Likes eines Genres entfernt es wieder aus top_genres (Watchlist-Entfernen-Fall)', async () => {
    await createGroup('p5', ['genre-user-5', 'p5-other']);
    const ref = await setSwipe('p5', 'genre-user-5', 740, 'like', { genreIds: [77] });
    await waitForPreferences('genre-user-5', (data) => (data.top_genres || []).includes(77));

    await ref.delete();

    const snap = await waitForPreferences('genre-user-5', (data) => !(data.top_genres || []).includes(77));

    assert.deepEqual(snap.data().top_genres, []);
    assert.equal(snap.data().genre_affinity['77'] ?? 0, 0);
  });

  it('6. Likes aus verschiedenen Gruppen desselben Users summieren sich in derselben Genre-Affinität', async () => {
    await createGroup('p6a', ['genre-user-6', 'p6a-other']);
    await createGroup('p6b', ['genre-user-6', 'p6b-other']);
    await setSwipe('p6a', 'genre-user-6', 750, 'like', { genreIds: [40] });
    await setSwipe('p6b', 'genre-user-6', 751, 'like', { genreIds: [40] });

    const snap = await waitForPreferences('genre-user-6', (data) => (data.genre_affinity || {})['40'] >= 1.9);

    assert.ok(snap.data().genre_affinity['40'] >= 1.9);
  });

  it('7. der Swipe eines anderen Users beeinflusst die eigenen Präferenzen nicht', async () => {
    await createGroup('p7', ['genre-user-7', 'genre-user-7b']);
    await setSwipe('p7', 'genre-user-7b', 760, 'like', { genreIds: [61] });

    await waitForPreferences('genre-user-7b', (data) => (data.top_genres || []).includes(61));
    const ownSnap = await preferencesRef('genre-user-7').get();

    assert.equal(ownSnap.exists, false);
  });

  it('8. Skip- und Watchlist-Swipes tragen nicht zur genre_affinity bei (nur "like" zählt)', async () => {
    await createGroup('p8', ['genre-user-8', 'p8-other']);
    await setSwipe('p8', 'genre-user-8', 770, 'skip', { genreIds: [12] });
    await setSwipe('p8', 'genre-user-8', 771, 'watchlist', { genreIds: [12] });
    // Ein anschließender Like in einem anderen Genre beweist, dass die
    // Function gelaufen ist.
    await setSwipe('p8', 'genre-user-8', 772, 'like', { genreIds: [13] });

    const snap = await waitForPreferences('genre-user-8', (data) => (data.top_genres || []).includes(13));

    assert.equal(snap.data().genre_affinity['12'] ?? 0, 0);
    assert.deepEqual(snap.data().top_genres, [13]);
  });
});
