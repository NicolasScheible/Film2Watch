'use strict';

const admin = require('firebase-admin');

/**
 * Wertet genau eine fällige Abstimmung aus (§21: "Filmabend-Abstimmung").
 * Gewinner ist der Terminvorschlag mit den meisten Stimmen; bei Gleichstand
 * gewinnt deterministisch der früheste Termin (mit dem Produktverantwortlichen
 * abgestimmt) - da [optionsSnap] nach `scheduled_at` aufsteigend sortiert
 * abgefragt wird, reicht dafür ein einfaches "> " (nicht ">=") beim
 * Durchlaufen: die erste Option mit der bisherigen Höchststimmenzahl bleibt
 * automatisch Gewinner, bis eine spätere Option sie tatsächlich übertrifft.
 * Hat niemand abgestimmt, bleibt der Gewinner `null` - kein erfundenes
 * Ergebnis ohne echte Stimme.
 *
 * Läuft ausschließlich mit Admin-Rechten (Scheduled Cloud Function bzw.
 * rules-bypassender Test-Context), niemals als client-aufrufbarer Endpunkt -
 * Firestore Security Rules verbieten jedem normalen Client das Schreiben von
 * `status`/`winning_option_id`/`result_movie_night_id` vollständig.
 *
 * Idempotent über eine Transaktion mit `status`-Prüfung: ein bereits
 * geschlossener Poll wird nie ein zweites Mal ausgewertet und erzeugt daher
 * auch nie einen zweiten `movie_nights`-Eintrag, selbst wenn die Scheduled
 * Cloud Function für dieselbe Abstimmung mehrfach läuft (z. B. weil sie beim
 * vorherigen Lauf knapp vor der Deadline nochmal gegriffen hat).
 *
 * @param {{ firestore: FirebaseFirestore.Firestore, pollRef: FirebaseFirestore.DocumentReference }} params
 * @returns {Promise<{ closed: boolean, groupId: string, winningOptionId: string|null, resultMovieNightId: string|null }>}
 */
async function resolveOnePoll({ firestore, pollRef }) {
  const groupId = pollRef.parent.parent.id;

  const [optionsSnap, votesSnap] = await Promise.all([
    pollRef.collection('options').orderBy('scheduled_at', 'asc').get(),
    pollRef.collection('votes').get(),
  ]);

  const voteCountByOptionId = new Map();
  for (const voteDoc of votesSnap.docs) {
    const optionId = voteDoc.data().option_id;
    if (typeof optionId !== 'string') continue;
    voteCountByOptionId.set(optionId, (voteCountByOptionId.get(optionId) || 0) + 1);
  }

  let winner = null;
  let winnerVoteCount = 0;
  for (const optionDoc of optionsSnap.docs) {
    const count = voteCountByOptionId.get(optionDoc.id) || 0;
    if (count > winnerVoteCount) {
      winner = optionDoc;
      winnerVoteCount = count;
    }
  }

  return firestore.runTransaction(async (transaction) => {
    const pollSnap = await transaction.get(pollRef);
    if (!pollSnap.exists || pollSnap.data().status !== 'open') {
      return { closed: false, groupId, winningOptionId: null, resultMovieNightId: null };
    }
    const pollData = pollSnap.data();

    let resultMovieNightId = null;
    if (winner) {
      const movieNightRef = firestore.collection('groups').doc(groupId).collection('movie_nights').doc();
      const winnerData = winner.data();
      const movieNightFields = {
        created_by: pollData.created_by,
        created_at: admin.firestore.FieldValue.serverTimestamp(),
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
        scheduled_at: winnerData.scheduled_at,
        platform_id: winnerData.platform_id,
      };
      if (typeof winnerData.movie_id === 'number') {
        movieNightFields.movie_id = winnerData.movie_id;
      }
      transaction.set(movieNightRef, movieNightFields);
      resultMovieNightId = movieNightRef.id;
    }

    transaction.update(pollRef, {
      status: 'closed',
      winning_option_id: winner ? winner.id : null,
      result_movie_night_id: resultMovieNightId,
      resolved_at: admin.firestore.FieldValue.serverTimestamp(),
    });

    return {
      closed: true,
      groupId,
      winningOptionId: winner ? winner.id : null,
      resultMovieNightId,
    };
  });
}

/**
 * Findet alle Abstimmungen gruppenübergreifend, deren Deadline erreicht ist
 * (Collection-Group-Query über `status`/`deadline`, siehe
 * `firestore.indexes.json`), und wertet jede davon aus. Läuft periodisch als
 * Scheduled Cloud Function (`functions/index.js`: `resolveMoviePolls`).
 *
 * @param {{ firestore: FirebaseFirestore.Firestore, now: Date }} params
 * @returns {Promise<Array<{ closed: boolean, groupId: string, winningOptionId: string|null, resultMovieNightId: string|null, pollRef: FirebaseFirestore.DocumentReference }>>}
 */
async function resolveDuePolls({ firestore, now }) {
  const snapshot = await firestore
    .collectionGroup('movie_night_polls')
    .where('status', '==', 'open')
    .where('deadline', '<=', now)
    .get();

  const results = [];
  for (const pollDoc of snapshot.docs) {
    const result = await resolveOnePoll({ firestore, pollRef: pollDoc.ref });
    results.push({ ...result, pollRef: pollDoc.ref });
  }
  return results;
}

module.exports = { resolveOnePoll, resolveDuePolls };
