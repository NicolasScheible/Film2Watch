'use strict';

const { sendToUsers, claimNotification } = require('./notifications');

/**
 * Benachrichtigt ALLE Mitglieder (inkl. des Erstellers) über das Ergebnis
 * einer automatisch ausgewerteten Filmabend-Abstimmung (§21) - anders als
 * bei `notifyMoviePollCreated`/`notifyMovieNightCreated` gibt es hier keine
 * eigene Nutzeraktion, die ausgeschlossen werden müsste: die Auswertung
 * kommt für alle Mitglieder gleichermaßen von der Scheduled Cloud Function.
 * Idempotent über [claimNotification] auf dem Poll-Dokument selbst - schützt
 * sowohl gegen eine erneute "at-least-once"-Zustellung des `onUpdate`-
 * Triggers als auch (indirekt) gegen einen erneuten Lauf der Scheduled
 * Cloud Function für dieselbe, bereits geschlossene Abstimmung.
 *
 * @param {{
 *   firestore: FirebaseFirestore.Firestore,
 *   messaging: { sendEachForMulticast: Function },
 *   groupId: string,
 *   pollRef: FirebaseFirestore.DocumentReference,
 *   winningOptionId: string|null,
 * }} params
 */
async function notifyMoviePollResolved({ firestore, messaging, groupId, pollRef, winningOptionId }) {
  const claimed = await claimNotification({ firestore, ref: pollRef, field: 'result_notified_at' });
  if (!claimed) return;

  const [groupSnapshot, membersSnapshot] = await Promise.all([
    firestore.collection('groups').doc(groupId).get(),
    firestore.collection('groups').doc(groupId).collection('members').get(),
  ]);

  const recipientUids = membersSnapshot.docs.map((doc) => doc.id);
  if (recipientUids.length === 0) return;

  const groupName = groupSnapshot.exists ? groupSnapshot.data().name : null;

  let body = 'Die Abstimmung ist beendet, aber niemand hat abgestimmt.';
  if (winningOptionId) {
    const optionSnapshot = await pollRef.collection('options').doc(winningOptionId).get();
    const scheduledAt = optionSnapshot.exists ? optionSnapshot.data().scheduled_at : null;
    body = scheduledAt
      ? `Der nächste Filmabend ist entschieden: ${scheduledAt.toDate().toLocaleString('de-DE')}.`
      : 'Der nächste Filmabend ist entschieden.';
  }

  await sendToUsers({
    firestore,
    messaging,
    uids: recipientUids,
    notification: {
      title: groupName ? `Abstimmung in ${groupName} beendet` : 'Abstimmung beendet',
      body,
    },
    data: { type: 'movie_poll', group_id: groupId },
  });
}

module.exports = { notifyMoviePollResolved };
