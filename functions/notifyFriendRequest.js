'use strict';

const { sendToUsers, claimNotification } = require('./notifications');

/**
 * Benachrichtigt den Empfänger einer neuen Freundschaftsanfrage. Der
 * Absender bekommt bewusst keine eigene Notification - er hat die Anfrage
 * selbst gerade gesendet und weiß bereits Bescheid.
 *
 * @param {{
 *   firestore: FirebaseFirestore.Firestore,
 *   messaging: { sendEachForMulticast: Function },
 *   requestId: string,
 *   fromUid: string,
 *   toUid: string,
 * }} params
 */
async function notifyFriendRequest({ firestore, messaging, requestId, fromUid, toUid }) {
  if (typeof fromUid !== 'string' || typeof toUid !== 'string' || !fromUid || !toUid) return;
  if (fromUid === toUid) return;

  const ref = firestore.collection('friend_requests').doc(requestId);
  const claimed = await claimNotification({ firestore, ref });
  if (!claimed) return;

  const senderProfile = await firestore.collection('public_profiles').doc(fromUid).get();
  const senderName = (senderProfile.exists && senderProfile.data().name) || 'Jemand';

  await sendToUsers({
    firestore,
    messaging,
    uids: [toUid],
    notification: {
      title: 'Neue Freundschaftsanfrage',
      body: `${senderName} möchte sich mit dir befreunden.`,
    },
    data: { type: 'friend_request' },
  });
}

module.exports = { notifyFriendRequest };
