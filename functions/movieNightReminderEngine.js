'use strict';

const { sendToUsers, claimNotification } = require('./notifications');

const ONE_DAY_MS = 24 * 60 * 60 * 1000;

/**
 * Sendet den zeitgesteuerten Reminder-Push für genau einen fälligen
 * Filmabend (§12/§21, mit dem Produktverantwortlichen abgestimmt: 1 Tag vor
 * dem Termin, zusätzlich zum bereits bestehenden Sofort-Push bei der
 * Erstellung - `notifyMovieNightCreated.js` bleibt unverändert). Anders als
 * dieser (der den Ersteller ausschließt) geht der Reminder an ALLE
 * Mitglieder inkl. des Erstellers - eine reine Server-Erinnerung ohne
 * ausschließenden "Akteur", analog zu `notifyMoviePollResolved`.
 *
 * Idempotent über [claimNotification] auf dem `movie_nights`-Dokument selbst
 * (Feld `reminder_sent_at`) - schützt sowohl gegen "at-least-once"-
 * Wiederholung eines einzelnen Scheduled-Function-Laufs als auch gegen
 * mehrfaches Greifen über mehrere Läufe hinweg. Eine spätere Bearbeitung des
 * Filmabends (`MovieNight.toFirestoreUpdate`) löscht `reminder_sent_at`
 * wieder - eine Terminverschiebung bekommt so zuverlässig einen neuen,
 * zum neuen Termin passenden Reminder.
 *
 * @param {{
 *   firestore: FirebaseFirestore.Firestore,
 *   messaging: { sendEachForMulticast: Function },
 *   movieNightRef: FirebaseFirestore.DocumentReference,
 *   groupId: string,
 *   scheduledAt: Date,
 * }} params
 * @returns {Promise<boolean>} true, wenn dieser Aufruf den Reminder tatsächlich versendet hat.
 */
async function sendMovieNightReminder({ firestore, messaging, movieNightRef, groupId, scheduledAt }) {
  const claimed = await claimNotification({ firestore, ref: movieNightRef, field: 'reminder_sent_at' });
  if (!claimed) return false;

  const [groupSnapshot, membersSnapshot] = await Promise.all([
    firestore.collection('groups').doc(groupId).get(),
    firestore.collection('groups').doc(groupId).collection('members').get(),
  ]);

  const recipientUids = membersSnapshot.docs.map((doc) => doc.id);
  if (recipientUids.length === 0) return true;

  const groupName = groupSnapshot.exists ? groupSnapshot.data().name : null;

  await sendToUsers({
    firestore,
    messaging,
    uids: recipientUids,
    notification: {
      title: groupName ? `Filmabend morgen in ${groupName}` : 'Filmabend morgen',
      body: `Euer Filmabend ist morgen um ${scheduledAt.toLocaleTimeString('de-DE', {
        hour: '2-digit',
        minute: '2-digit',
      })} Uhr.`,
    },
    data: { type: 'movie_night', group_id: groupId },
  });
  return true;
}

/**
 * Findet alle Filmabende gruppenübergreifend, deren Termin innerhalb der
 * nächsten 24 Stunden liegt, und versendet für jeden davon (sofern noch
 * nicht geschehen) den Reminder. Läuft periodisch als Scheduled Cloud
 * Function (`functions/index.js`: `sendMovieNightReminders`).
 *
 * Filtert `reminder_sent_at` bewusst erst nach der Query in JavaScript statt
 * über eine zusätzliche Firestore-Bedingung: eine reine `scheduled_at`-
 * Bereichsabfrage braucht keinen zusätzlichen Composite-Index (anders als
 * `resolveDuePolls`, das nach `status` UND `deadline` filtert).
 *
 * @param {{ firestore: FirebaseFirestore.Firestore, messaging: { sendEachForMulticast: Function }, now: Date }} params
 * @returns {Promise<{ checked: number, sent: number }>}
 */
async function sendDueMovieNightReminders({ firestore, messaging, now }) {
  const windowEnd = new Date(now.getTime() + ONE_DAY_MS);
  const snapshot = await firestore
    .collectionGroup('movie_nights')
    .where('scheduled_at', '>', now)
    .where('scheduled_at', '<=', windowEnd)
    .get();

  let sent = 0;
  for (const doc of snapshot.docs) {
    const data = doc.data();
    if (data.reminder_sent_at) continue;

    const groupId = doc.ref.parent.parent.id;
    const scheduledAt = data.scheduled_at.toDate();
    const didSend = await sendMovieNightReminder({
      firestore,
      messaging,
      movieNightRef: doc.ref,
      groupId,
      scheduledAt,
    });
    if (didSend) sent++;
  }

  return { checked: snapshot.docs.length, sent };
}

module.exports = { sendMovieNightReminder, sendDueMovieNightReminders };
