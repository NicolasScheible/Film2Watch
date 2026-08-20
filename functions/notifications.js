'use strict';

/**
 * Lädt alle Device-Tokens der angegebenen User-IDs und versendet die
 * Notification per Multicast. Tokens, die FCM als nicht mehr registriert
 * meldet, werden anschließend aus Firestore entfernt - kein endloses
 * erneutes Zustellen an tote Tokens. Wirft absichtlich nie: ein
 * fehlgeschlagener Versand darf den aufrufenden Firestore-Trigger nie zum
 * Scheitern bringen (der eigentliche Firestore-Hauptvorgang - Anfrage,
 * Einladung, Match, Nachricht - ist zu diesem Zeitpunkt bereits
 * abgeschlossen und unabhängig vom Notification-Versand).
 *
 * @param {{
 *   firestore: FirebaseFirestore.Firestore,
 *   messaging: { sendEachForMulticast: Function },
 *   uids: string[],
 *   notification: { title: string, body: string },
 *   data: Record<string, string>,
 * }} params
 * @returns {Promise<{ sentCount: number }>}
 */
async function sendToUsers({ firestore, messaging, uids, notification, data }) {
  const uniqueUids = [...new Set(uids)];
  if (uniqueUids.length === 0) return { sentCount: 0 };

  const devices = [];
  for (const uid of uniqueUids) {
    const snapshot = await firestore.collection('users').doc(uid).collection('devices').get();
    for (const doc of snapshot.docs) {
      const token = doc.data().token;
      if (typeof token === 'string' && token.length > 0) {
        devices.push({ token, ref: doc.ref });
      }
    }
  }
  if (devices.length === 0) return { sentCount: 0 };

  let sentCount = 0;
  // FCM erlaubt maximal 500 Tokens pro Multicast-Aufruf.
  for (let i = 0; i < devices.length; i += 500) {
    const batch = devices.slice(i, i + 500);
    try {
      const response = await messaging.sendEachForMulticast({
        tokens: batch.map((device) => device.token),
        notification,
        data,
      });
      sentCount += response.successCount;

      await Promise.all(
        response.responses.map((result, index) => {
          if (result.success) return null;
          const code = result.error && result.error.code;
          const tokenInvalid =
            code === 'messaging/registration-token-not-registered' ||
            code === 'messaging/invalid-registration-token';
          if (!tokenInvalid) return null;
          return batch[index].ref.delete().catch(() => null);
        }),
      );
    } catch {
      // Ein fehlgeschlagener Batch darf weder crashen noch weitere Batches
      // verhindern.
    }
  }
  return { sentCount };
}

/**
 * Beansprucht das Recht, für [ref] genau einmal eine bestimmte Aktion
 * auszuführen (z. B. eine Notification zu versenden) - schützt gegen Cloud
 * Functions' "at-least-once"-Zustellung (derselbe Trigger kann in seltenen
 * Fällen erneut ausgeführt werden). Atomar über eine Transaktion: nur der
 * erste erfolgreiche Aufruf für ein gegebenes Dokument+Feld liefert `true`,
 * jeder weitere `false`.
 *
 * [field] erlaubt mehrere unabhängige Claims auf demselben Dokument (z. B.
 * Push-Notification und Chat-Systemnachricht für dasselbe Match) - jede
 * Aktion beansprucht ihr eigenes Marker-Feld, ohne sich gegenseitig zu
 * blockieren.
 *
 * @param {{ firestore: FirebaseFirestore.Firestore, ref: FirebaseFirestore.DocumentReference, field?: string }} params
 * @returns {Promise<boolean>}
 */
async function claimNotification({ firestore, ref, field = 'notified_at' }) {
  return firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (!snapshot.exists) return false;
    if (snapshot.data()[field]) return false;
    transaction.update(ref, { [field]: new Date() });
    return true;
  });
}

module.exports = { sendToUsers, claimNotification };
