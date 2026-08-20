'use strict';

const { sendToUsers, claimNotification } = require('./notifications');

/**
 * Benachrichtigt die eingeladene Person über eine neue Gruppeneinladung.
 * Niemand sonst (auch nicht der Inviter selbst) bekommt eine Notification.
 *
 * @param {{
 *   firestore: FirebaseFirestore.Firestore,
 *   messaging: { sendEachForMulticast: Function },
 *   invitationId: string,
 *   groupId: string,
 *   inviteeUid: string,
 * }} params
 */
async function notifyGroupInvitation({ firestore, messaging, invitationId, groupId, inviteeUid }) {
  if (typeof groupId !== 'string' || typeof inviteeUid !== 'string' || !groupId || !inviteeUid) return;

  const ref = firestore.collection('group_invitations').doc(invitationId);
  const claimed = await claimNotification({ firestore, ref });
  if (!claimed) return;

  const groupSnapshot = await firestore.collection('groups').doc(groupId).get();
  const groupName = (groupSnapshot.exists && groupSnapshot.data().name) || 'einer Gruppe';

  await sendToUsers({
    firestore,
    messaging,
    uids: [inviteeUid],
    notification: {
      title: 'Neue Gruppeneinladung',
      body: `Du wurdest zu "${groupName}" eingeladen.`,
    },
    data: { type: 'group_invitation', group_id: groupId },
  });
}

module.exports = { notifyGroupInvitation };
