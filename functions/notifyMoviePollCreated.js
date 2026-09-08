'use strict';

const { sendToUsers, claimNotification } = require('./notifications');

/**
 * Benachrichtigt alle Gruppenmitglieder außer dem Ersteller über eine neu
 * angelegte Filmabend-Abstimmung (§21) - identisches Muster zu
 * `notifyMovieNightCreated.js`. Der Ersteller bekommt nie eine eigene
 * Notification für die eigene Aktion.
 *
 * @param {{
 *   firestore: FirebaseFirestore.Firestore,
 *   messaging: { sendEachForMulticast: Function },
 *   groupId: string,
 *   pollRef: FirebaseFirestore.DocumentReference,
 *   createdBy: string,
 * }} params
 */
async function notifyMoviePollCreated({ firestore, messaging, groupId, pollRef, createdBy }) {
  if (typeof createdBy !== 'string' || !createdBy) return;

  const claimed = await claimNotification({ firestore, ref: pollRef });
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
      title: groupName ? `Neue Abstimmung in ${groupName}` : 'Neue Filmabend-Abstimmung',
      body: `${creatorName} hat eine Abstimmung für den nächsten Filmabend gestartet.`,
    },
    data: { type: 'movie_poll', group_id: groupId },
  });
}

module.exports = { notifyMoviePollCreated };
