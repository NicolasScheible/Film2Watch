'use strict';

/**
 * Pflegt `users/{uid}/groups/{groupId}` - einen rein technischen, ausschließlich
 * serverseitig gepflegten Index (keine neue fachliche Datenquelle), der es dem
 * Client erlaubt, die eigenen groupIds sicher zu bestimmen. Ersetzt die zuvor
 * dafür verwendete `collectionGroup('members').where('uid', ...)`-Query, die
 * unter den Firestore Security Rules als Query (anders als ein `get()` auf
 * einen einzelnen, vollständig bekannten Pfad) nicht beweisbar ist und daher
 * mit `permission-denied` abgelehnt wird - siehe README, Abschnitt
 * "Vorbestehender technischer Befund: watchMyGroups()/myGroupCount()".
 *
 * Wird von `onGroupMemberWritten` (siehe `functions/index.js`) bei jedem
 * tatsächlichen Anlegen/Löschen einer `groups/{groupId}/members/{memberUid}`-
 * Mitgliedschaft aufgerufen - exakt derselbe Trigger-Zeitpunkt wie
 * `applyMembershipCountDelta`, aber ein eigenständiger Zweck: der Index dient
 * ausschließlich dem sicheren Auflisten der eigenen Gruppen, während
 * `group_membership_counts` weiterhin exklusiv die §15-Limit-Zähllogik
 * bedient. Beide Strukturen bleiben unabhängig voneinander bestehen.
 *
 * `set()`/`delete()` auf einem vollständig bekannten Dokumentpfad sind von
 * Natur aus idempotent - ein wiederholter Aufruf mit demselben `exists`-Wert
 * (z. B. durch einen erneuten Trigger-Lauf oder das Backfill-Skript) erzeugt
 * keinen falschen oder doppelten Zustand.
 *
 * @param {{ firestore: FirebaseFirestore.Firestore, uid: string, groupId: string, exists: boolean }} params
 */
async function applyUserGroupIndexEntry({ firestore, uid, groupId, exists }) {
  const ref = firestore.doc(`users/${uid}/groups/${groupId}`);
  if (exists) {
    await ref.set({ groupId });
  } else {
    await ref.delete();
  }
}

module.exports = { applyUserGroupIndexEntry };
