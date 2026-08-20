'use strict';

const { claimNotification } = require('./notifications');

/**
 * Postet eine System-Nachricht in den Gruppenchat, sobald ein Match
 * entstanden ist - damit das Match auch für Mitglieder sichtbar bleibt, die
 * die Push-Notification verpassen oder erst später in den Chatverlauf
 * schauen (siehe `notifyMatch.js` für den Push-Versand). Beide Aktionen
 * laufen unabhängig voneinander auf demselben Match-Dokument (getrennte
 * `claimNotification`-Felder), damit ein Fehlschlag der einen die andere
 * nicht verhindert.
 *
 * Enthält bewusst nur `movie_id`, keinen Filmtitel: Cloud Functions haben
 * keinen TMDB-Zugriff und sollen auch keinen bekommen (siehe `notifyMatch.js`
 * für dieselbe Begründung) - der Client löst den Film clientseitig über
 * `movieDetailsProvider` auf.
 *
 * @param {{
 *   firestore: FirebaseFirestore.Firestore,
 *   groupId: string,
 *   matchRef: FirebaseFirestore.DocumentReference,
 *   movieId: number,
 * }} params
 */
async function postMatchChatMessage({ firestore, groupId, matchRef, movieId }) {
  const claimed = await claimNotification({
    firestore,
    ref: matchRef,
    field: 'chat_message_posted_at',
  });
  if (!claimed) return;

  await firestore.collection('groups').doc(groupId).collection('messages').add({
    type: 'match',
    movie_id: movieId,
    created_at: new Date(),
  });
}

module.exports = { postMatchChatMessage };
