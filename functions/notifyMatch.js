'use strict';

const { sendToUsers, claimNotification } = require('./notifications');

/**
 * Benachrichtigt alle aktuellen Mitglieder einer Gruppe über ein neu
 * entstandenes Match. Enthält bewusst den Gruppennamen statt des
 * Filmtitels: Filmdaten kommen ausschließlich von TMDB (clientseitig,
 * siehe `lib/repositories/movie_repository.dart`) - Cloud Functions haben
 * keinen TMDB-Zugriff und sollen auch keinen bekommen, um TMDB nicht zu
 * duplizieren. Der Filmtitel erscheint clientseitig nach dem Antippen
 * (Deep Link zur Gruppe, die bestehende Match-/Filmdetail-Anzeige lädt ihn
 * live nach).
 *
 * Es gibt keinen separaten "Ersteller" des Match-Ereignisses, der
 * ausgeschlossen werden müsste - ein Match ist ein gemeinsames, serverseitig
 * ermitteltes Ergebnis aller Mitglieder gleichzeitig; [claimNotification]
 * stellt sicher, dass dafür in jedem Fall nur genau eine Notification-Runde
 * verschickt wird (keine Duplikate durch erneute Trigger-Ausführung).
 *
 * @param {{
 *   firestore: FirebaseFirestore.Firestore,
 *   messaging: { sendEachForMulticast: Function },
 *   groupId: string,
 *   matchRef: FirebaseFirestore.DocumentReference,
 * }} params
 */
async function notifyMatch({ firestore, messaging, groupId, matchRef }) {
  const claimed = await claimNotification({ firestore, ref: matchRef });
  if (!claimed) return;

  const groupSnapshot = await firestore.collection('groups').doc(groupId).get();
  const groupName = (groupSnapshot.exists && groupSnapshot.data().name) || 'deiner Gruppe';

  const membersSnapshot = await firestore.collection('groups').doc(groupId).collection('members').get();
  const uids = membersSnapshot.docs.map((doc) => doc.id);

  await sendToUsers({
    firestore,
    messaging,
    uids,
    notification: {
      title: 'Neuer Match! 🍿',
      body: `Ihr habt in "${groupName}" einen gemeinsamen Film gefunden.`,
    },
    data: { type: 'match', group_id: groupId },
  });
}

module.exports = { notifyMatch };
