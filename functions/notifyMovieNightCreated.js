'use strict';

const { sendToUsers, claimNotification } = require('./notifications');

/**
 * Benachrichtigt alle Gruppenmitglieder außer dem Ersteller über einen neu
 * geplanten Filmabend (§12: "Filmabend planen" - Reminder-Push bei
 * Erstellung, kein zeitgesteuerter Reminder, mit dem Produktverantwortlichen
 * abgestimmt). Der Ersteller bekommt nie eine eigene Notification -
 * identisches Muster zu `notifyChatMessage.js`.
 *
 * @param {{
 *   firestore: FirebaseFirestore.Firestore,
 *   messaging: { sendEachForMulticast: Function },
 *   groupId: string,
 *   movieNightRef: FirebaseFirestore.DocumentReference,
 *   createdBy: string,
 * }} params
 */
async function notifyMovieNightCreated({ firestore, messaging, groupId, movieNightRef, createdBy }) {
  if (typeof createdBy !== 'string' || !createdBy) return;

  const claimed = await claimNotification({ firestore, ref: movieNightRef });
  if (!claimed) return;

  const [groupSnapshot, creatorSnapshot, membersSnapshot] = await Promise.all([
    firestore.collection('groups').doc(groupId).get(),
    firestore.collection('public_profiles').doc(createdBy).get(),
    firestore.collection('groups').doc(groupId).collection('members').get(),
  ]);

  const recipientUids = membersSnapshot.docs.map((doc) => doc.id).filter((uid) => uid !== createdBy);
  if (recipientUids.length === 0) return;

  const groupName = groupSnapshot.exists ? groupSnapshot.data().name : null;
  const creatorName = (creatorSnapshot.exists && creatorSnapshot.data().name) || 'Jemand';

  await sendToUsers({
    firestore,
    messaging,
    uids: recipientUids,
    notification: {
      title: groupName ? `Neuer Filmabend in ${groupName}` : 'Neuer Filmabend',
      body: `${creatorName} hat einen Filmabend geplant.`,
    },
    data: { type: 'movie_night', group_id: groupId },
  });
}

module.exports = { notifyMovieNightCreated };
