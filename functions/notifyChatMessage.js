'use strict';

const { sendToUsers, claimNotification } = require('./notifications');

const _previewMaxLength = 80;

/**
 * Benachrichtigt alle Gruppenmitglieder außer dem Absender über eine neue
 * Chat-Nachricht. Der Absender bekommt nie eine eigene Notification. Die
 * Vorschau wird gekürzt (Privacy: keine unnötig langen Nachrichteninhalte
 * im Notification-Payload).
 *
 * @param {{
 *   firestore: FirebaseFirestore.Firestore,
 *   messaging: { sendEachForMulticast: Function },
 *   groupId: string,
 *   messageRef: FirebaseFirestore.DocumentReference,
 *   senderUid: string,
 *   text: string,
 * }} params
 */
async function notifyChatMessage({ firestore, messaging, groupId, messageRef, senderUid, text }) {
  if (typeof senderUid !== 'string' || !senderUid) return;

  const claimed = await claimNotification({ firestore, ref: messageRef });
  if (!claimed) return;

  const [groupSnapshot, senderSnapshot, membersSnapshot] = await Promise.all([
    firestore.collection('groups').doc(groupId).get(),
    firestore.collection('public_profiles').doc(senderUid).get(),
    firestore.collection('groups').doc(groupId).collection('members').get(),
  ]);

  const recipientUids = membersSnapshot.docs.map((doc) => doc.id).filter((uid) => uid !== senderUid);
  if (recipientUids.length === 0) return;

  const groupName = groupSnapshot.exists ? groupSnapshot.data().name : null;
  const senderName = (senderSnapshot.exists && senderSnapshot.data().name) || 'Jemand';
  const preview =
    typeof text === 'string' && text.length > _previewMaxLength
      ? `${text.slice(0, _previewMaxLength)}…`
      : text || '';

  await sendToUsers({
    firestore,
    messaging,
    uids: recipientUids,
    notification: {
      title: groupName ? `${senderName} in ${groupName}` : `Neue Nachricht von ${senderName}`,
      body: preview,
    },
    data: { type: 'chat_message', group_id: groupId },
  });
}

module.exports = { notifyChatMessage };
