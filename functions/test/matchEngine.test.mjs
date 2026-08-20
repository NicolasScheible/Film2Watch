import assert from 'node:assert/strict';
import { before, describe, it } from 'node:test';
import admin from 'firebase-admin';
import { evaluateMatch } from '../matchEngine.js';

// End-to-End-Test der echten Cloud Function `onSwipeWritten` (siehe
// index.js) gegen den echten Firebase Functions Emulator + Firestore
// Emulator (gestartet über `firebase emulators:start --only firestore,functions`).
// Es wird bewusst NICHT nur die reine matchEngine-Funktion direkt
// aufgerufen, sondern über echte Firestore-Writes der komplette Trigger-Pfad
// durchlaufen - das deckt auch Trigger-Registrierung/-Routing ab.

const PROJECT_ID = process.env.GCLOUD_PROJECT || 'film2watch-rules-test';

let db;

before(() => {
  admin.initializeApp({ projectId: PROJECT_ID });
  db = admin.firestore();
});

const now = () => new Date();

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

async function setSwipe(groupId, uid, movieId, decision) {
  const ref = db.doc(`groups/${groupId}/swipes/${uid}_${movieId}`);
  const existing = await ref.get();
  if (existing.exists) {
    await ref.update({ decision, updated_at: now() });
  } else {
    await ref.set({ uid, movie_id: movieId, decision, created_at: now(), updated_at: now() });
  }
}

function matchRef(groupId, movieId) {
  return db.doc(`groups/${groupId}/matches/${movieId}`);
}

/** Wartet, bis die (asynchrone) Cloud Function das Match-Dokument angelegt hat. */
async function waitForMatch(groupId, movieId, { timeoutMs = 10000, intervalMs = 200 } = {}) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const snap = await matchRef(groupId, movieId).get();
    if (snap.exists) return snap;
    await new Promise((resolve) => setTimeout(resolve, intervalMs));
  }
  return matchRef(groupId, movieId).get();
}

/** Wartet eine feste Zeit und verifiziert dann, dass (noch) kein Match existiert. */
async function assertNoMatchAfterSettling(groupId, movieId, waitMs = 3000) {
  await new Promise((resolve) => setTimeout(resolve, waitMs));
  const snap = await matchRef(groupId, movieId).get();
  assert.equal(snap.exists, false, `Unerwartetes Match-Dokument für Film ${movieId} in ${groupId}`);
}

describe('onSwipeWritten -> Match-Erkennung (echter Functions-Emulator)', () => {
  it('1. 2 Mitglieder + beide Like -> Match', async () => {
    await createGroup('g1', ['alice', 'bob']);
    await setSwipe('g1', 'alice', 601, 'like');
    await setSwipe('g1', 'bob', 601, 'like');

    const snap = await waitForMatch('g1', 601);
    assert.equal(snap.exists, true);
    assert.deepEqual(snap.data().member_uids, ['alice', 'bob']);
  });

  it('2. 2 Mitglieder + ein Like/ein Dislike -> kein Match', async () => {
    await createGroup('g2', ['alice', 'bob']);
    await setSwipe('g2', 'alice', 602, 'like');
    await setSwipe('g2', 'bob', 602, 'dislike');

    await assertNoMatchAfterSettling('g2', 602);
  });

  it('3. 2 Mitglieder + nur ein Like -> kein Match', async () => {
    await createGroup('g3', ['alice', 'bob']);
    await setSwipe('g3', 'alice', 603, 'like');

    await assertNoMatchAfterSettling('g3', 603);
  });

  it('4. 3 Mitglieder + 2 Likes -> kein Match', async () => {
    await createGroup('g4', ['alice', 'bob', 'carol']);
    await setSwipe('g4', 'alice', 604, 'like');
    await setSwipe('g4', 'bob', 604, 'like');

    await assertNoMatchAfterSettling('g4', 604);
  });

  it('5. 3 Mitglieder + 3 Likes -> Match', async () => {
    await createGroup('g5', ['alice', 'bob', 'carol']);
    await setSwipe('g5', 'alice', 605, 'like');
    await setSwipe('g5', 'bob', 605, 'like');
    await setSwipe('g5', 'carol', 605, 'like');

    const snap = await waitForMatch('g5', 605);
    assert.equal(snap.exists, true);
    assert.deepEqual(snap.data().member_uids, ['alice', 'bob', 'carol']);
  });

  it('6. bereits bestehender Match -> kein Duplikat', async () => {
    await createGroup('g6', ['alice', 'bob']);
    await setSwipe('g6', 'alice', 606, 'like');
    await setSwipe('g6', 'bob', 606, 'like');
    const first = await waitForMatch('g6', 606);
    assert.equal(first.exists, true);
    const originalMatchedAt = first.data().matched_at.toMillis();

    // Erneuter Schreibvorgang (z. B. erneutes Bestätigen des Likes) darf das
    // bestehende Match-Dokument nicht duplizieren oder überschreiben.
    await setSwipe('g6', 'alice', 606, 'like');
    await new Promise((resolve) => setTimeout(resolve, 2000));

    const second = await matchRef('g6', 606).get();
    assert.equal(second.data().matched_at.toMillis(), originalMatchedAt);
    const allMatches = await db.collection('groups/g6/matches').get();
    assert.equal(allMatches.size, 1);
  });

  it('7. Like -> Dislike korrekt behandelt, solange noch kein Match entstanden ist', async () => {
    await createGroup('g7', ['alice', 'bob', 'carol']);
    await setSwipe('g7', 'alice', 607, 'like');
    await setSwipe('g7', 'bob', 607, 'like');
    // Noch kein Match (carol fehlt). Alice überlegt es sich anders:
    await setSwipe('g7', 'alice', 607, 'dislike');
    await setSwipe('g7', 'carol', 607, 'like');

    // bob+carol like, alice dislike -> weiterhin kein Match.
    await assertNoMatchAfterSettling('g7', 607);
  });

  it('8. Dislike -> Like korrekt behandelt und kann zum Match führen', async () => {
    await createGroup('g8', ['alice', 'bob']);
    await setSwipe('g8', 'bob', 608, 'dislike');
    await setSwipe('g8', 'alice', 608, 'like');
    await assertNoMatchAfterSettling('g8', 608, 1500);

    await setSwipe('g8', 'bob', 608, 'like');
    const snap = await waitForMatch('g8', 608);
    assert.equal(snap.exists, true);
  });

  it('9. Swipe eines Nicht-(mehr-)Mitglieds zählt nicht mit', async () => {
    await createGroup('g9', ['alice', 'bob']);
    // "dave" ist kein Mitglied von g9, hat aber (z. B. vor dem Verlassen der
    // Gruppe) einen Like-Swipe für denselben Film hinterlassen.
    await db.doc('groups/g9/swipes/dave_609').set({
      uid: 'dave',
      movie_id: 609,
      decision: 'like',
      created_at: now(),
      updated_at: now(),
    });
    await setSwipe('g9', 'alice', 609, 'like');
    // bob liked NICHT - ohne die Korrektur würde daves fremder Like sonst
    // fälschlich die Mitgliederzahl "erfüllen".
    await assertNoMatchAfterSettling('g9', 609);
  });

  it('10. falsche Group-ID -> evaluateMatch wirft einen Fehler', async () => {
    await assert.rejects(
      () => evaluateMatch({ firestore: db, groupId: 'does-not-exist-xyz', movieId: 1 }),
      /existiert nicht/,
    );
  });

  it('11. fehlender/ungültiger Film -> evaluateMatch wirft einen sauberen Fehler', async () => {
    await assert.rejects(
      () => evaluateMatch({ firestore: db, groupId: 'g1', movieId: Number.NaN }),
      /ungültige movieId/,
    );
  });

  it('12. mehrere Filme werden unabhängig voneinander behandelt', async () => {
    await createGroup('g12', ['alice', 'bob']);
    await setSwipe('g12', 'alice', 611, 'like');
    await setSwipe('g12', 'bob', 611, 'like');
    await setSwipe('g12', 'alice', 612, 'like');
    await setSwipe('g12', 'bob', 612, 'like');

    const [match611, match612] = await Promise.all([
      waitForMatch('g12', 611),
      waitForMatch('g12', 612),
    ]);
    assert.equal(match611.exists, true);
    assert.equal(match612.exists, true);

    // Eine spätere Meinungsänderung zu Film 611 darf Match 612 nicht berühren.
    await setSwipe('g12', 'alice', 611, 'dislike');
    await new Promise((resolve) => setTimeout(resolve, 1500));
    const stillMatch612 = await matchRef('g12', 612).get();
    assert.equal(stillMatch612.exists, true);
  });

  it('13. echte parallele Verarbeitung erzeugt konsistent genau ein Match-Dokument', async () => {
    await createGroup('g13', ['alice', 'bob', 'carol']);
    await setSwipe('g13', 'alice', 613, 'like');
    await setSwipe('g13', 'bob', 613, 'like');
    await setSwipe('g13', 'carol', 613, 'like');

    // Ruft evaluateMatch (dieselbe Funktion, die der echte Trigger nutzt)
    // absichtlich mehrfach *gleichzeitig* auf - simuliert mehrere parallel
    // ausgeführte Trigger-Instanzen für dasselbe Ereignis (Cloud Functions
    // garantieren nur "at-least-once"-Zustellung). Die Firestore-Transaktion
    // in matchEngine.js muss das serialisieren, ohne ein Duplikat oder einen
    // inkonsistenten Zustand zu erzeugen.
    await Promise.all([
      evaluateMatch({ firestore: db, groupId: 'g13', movieId: 613 }),
      evaluateMatch({ firestore: db, groupId: 'g13', movieId: 613 }),
      evaluateMatch({ firestore: db, groupId: 'g13', movieId: 613 }),
      evaluateMatch({ firestore: db, groupId: 'g13', movieId: 613 }),
      evaluateMatch({ firestore: db, groupId: 'g13', movieId: 613 }),
    ]);

    const allMatches = await db.collection('groups/g13/matches').get();
    assert.equal(allMatches.size, 1);
    assert.deepEqual(allMatches.docs[0].data().member_uids, ['alice', 'bob', 'carol']);
  });

  it('14. Skip + Like erzeugt keinen Match (Skip zählt weder als Like noch als Dislike)', async () => {
    await createGroup('g14', ['alice', 'bob']);
    await setSwipe('g14', 'alice', 614, 'skip');
    await setSwipe('g14', 'bob', 614, 'like');

    await assertNoMatchAfterSettling('g14', 614);
  });

  it('15. andere Mitglieder können trotz eines Skips weiterhin unabhängig liken, und ein Match entsteht für einen anderen Film, wenn alle Mitglieder liken',
      async () => {
    await createGroup('g15', ['alice', 'bob', 'carol']);
    // Alice skippt Film 615 - das darf weder diesen noch einen anderen Film
    // der Gruppe beeinträchtigen.
    await setSwipe('g15', 'alice', 615, 'skip');

    // Bob und Carol können Film 615 unabhängig von Alice' Skip weiterhin
    // ganz normal bewerten.
    await setSwipe('g15', 'bob', 615, 'like');
    await setSwipe('g15', 'carol', 615, 'dislike');
    await assertNoMatchAfterSettling('g15', 615);

    // Ein völlig anderer Film, den alle drei Mitglieder liken, matcht
    // weiterhin normal - Alice' Skip auf Film 615 hat keinerlei Auswirkung
    // auf die Match-Erkennung für Film 616.
    await setSwipe('g15', 'alice', 616, 'like');
    await setSwipe('g15', 'bob', 616, 'like');
    await setSwipe('g15', 'carol', 616, 'like');
    const snap = await waitForMatch('g15', 616);
    assert.equal(snap.exists, true);
    assert.deepEqual(snap.data().member_uids, ['alice', 'bob', 'carol']);

    // Weiterhin kein Match für den geskippten Film 615.
    const stillNoMatch = await matchRef('g15', 615).get();
    assert.equal(stillNoMatch.exists, false);
  });

  it('16. Watchlist + Watchlist erzeugt keinen Match', async () => {
    await createGroup('g16', ['alice', 'bob']);
    await setSwipe('g16', 'alice', 617, 'watchlist');
    await setSwipe('g16', 'bob', 617, 'watchlist');

    await assertNoMatchAfterSettling('g16', 617);
  });

  it('17. Watchlist + Like erzeugt keinen Match (Watchlist zählt weder als Like noch als Dislike)', async () => {
    await createGroup('g17', ['alice', 'bob']);
    await setSwipe('g17', 'alice', 618, 'watchlist');
    await setSwipe('g17', 'bob', 618, 'like');

    await assertNoMatchAfterSettling('g17', 618);
  });

  it('18. andere Mitglieder können trotz einer Watchlist-Entscheidung weiterhin unabhängig liken, und ein Match entsteht für einen anderen Film, wenn alle Mitglieder liken',
      async () => {
    await createGroup('g18', ['alice', 'bob', 'carol']);
    // Alice setzt Film 619 auf ihre persönliche Watchlist - das darf weder
    // diesen noch einen anderen Film der Gruppe beeinträchtigen.
    await setSwipe('g18', 'alice', 619, 'watchlist');

    // Bob und Carol können Film 619 unabhängig von Alice' Watchlist-Eintrag
    // weiterhin ganz normal bewerten.
    await setSwipe('g18', 'bob', 619, 'like');
    await setSwipe('g18', 'carol', 619, 'dislike');
    await assertNoMatchAfterSettling('g18', 619);

    // Ein völlig anderer Film, den alle drei Mitglieder liken, matcht
    // weiterhin normal - Alice' Watchlist-Eintrag zu Film 619 hat keinerlei
    // Auswirkung auf die Match-Erkennung für Film 620.
    await setSwipe('g18', 'alice', 620, 'like');
    await setSwipe('g18', 'bob', 620, 'like');
    await setSwipe('g18', 'carol', 620, 'like');
    const snap = await waitForMatch('g18', 620);
    assert.equal(snap.exists, true);
    assert.deepEqual(snap.data().member_uids, ['alice', 'bob', 'carol']);

    // Weiterhin kein Match für den Film auf der Watchlist.
    const stillNoMatch = await matchRef('g18', 619).get();
    assert.equal(stillNoMatch.exists, false);
  });
});
