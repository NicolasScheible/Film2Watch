'use strict';

/**
 * Pflegt `users/{uid}/swiped_groups/{groupId}` - einen dauerhaften, NIEMALS
 * wieder entfernten Index aller Gruppen, in denen [uid] jemals mindestens
 * einmal geswiped hat (PO-Entscheidung: §15 "Detaillierte Statistiken" soll
 * auch Swipes aus inzwischen verlassenen Gruppen zählen, siehe README
 * "Architekturentscheidung"). Anders als `users/{uid}/groups/{groupId}`
 * (aktuelle Mitgliedschaft, wird beim Verlassen der Gruppe gelöscht, siehe
 * `userGroupIndex.js`) bleibt dieser Index absichtlich für immer bestehen -
 * Swipe-Dokumente selbst werden beim Verlassen einer Gruppe ebenfalls nicht
 * gelöscht (unverändertes, bestehendes Verhalten von
 * `GroupService.leaveGroup`/`removeMember`).
 *
 * Wird von `onSwipeWrittenForGroupIndex` (siehe `functions/index.js`)
 * ausschließlich beim ERSTMALIGEN Anlegen eines Swipe-Dokuments aufgerufen -
 * ein erneutes Bewerten (update) oder Löschen (z. B. Watchlist-Entfernen)
 * ändert nichts an der Tatsache, dass der User in dieser Gruppe bereits
 * geswiped hat, und wird daher bewusst ignoriert.
 *
 * `set()` auf einen deterministischen Dokumentpfad ist idempotent - ein
 * wiederholter Aufruf (z. B. ein weiterer Film in derselben Gruppe)
 * überschreibt den bestehenden Eintrag lediglich mit sich selbst.
 *
 * @param {{ firestore: FirebaseFirestore.Firestore, uid: string, groupId: string }} params
 */
async function markGroupAsSwiped({ firestore, uid, groupId }) {
  await firestore.doc(`users/${uid}/swiped_groups/${groupId}`).set({ groupId });
}

module.exports = { markGroupAsSwiped };
