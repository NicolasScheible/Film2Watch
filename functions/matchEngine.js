'use strict';

/**
 * Serverseitige Match-Erkennung. Läuft ausschließlich mit Admin-Rechten
 * (Cloud Function bzw. rules-bypassender Test-Context) - niemals als
 * client-aufrufbarer Endpunkt. Firestore Security Rules verbieten jedem
 * normalen Client das Schreiben von `groups/{groupId}/matches/{movieId}`
 * vollständig; nur dieser Code darf Match-Dokumente erzeugen.
 *
 * Match-Regel: ein Film ist ein Gruppen-Match, sobald *jedes* aktuelle
 * Mitglied der Gruppe ihn geliked hat (Dislike verhindert den Match für
 * diesen Film; ein fehlender Swipe zählt ebenfalls als "noch kein Match").
 * Das deckt automatisch beliebige Gruppengrößen ab, da die aktuelle
 * Mitgliederliste bei jeder Auswertung frisch abgefragt wird.
 *
 * WICHTIG: Es wird bewusst pro Mitglieds-UID geprüft (nicht nur eine
 * Like-Anzahl gegen die Mitgliederzahl gezählt) - ein Swipe-Dokument eines
 * Users, der die Gruppe zwischenzeitlich verlassen hat, darf nicht
 * fälschlich als "ein Mitglied hat geliked" mitzählen.
 *
 * Ein einmal entstandenes Match ist ein endgültiges Ergebnis: ändert ein
 * Mitglied seine Bewertung später (Like -> Dislike) oder verlässt die
 * Gruppe, wird ein bereits existierendes Match-Dokument NICHT rückwirkend
 * gelöscht oder verändert - es bleibt als dauerhafter Beleg bestehen, analog
 * zu einem klassischen "Match" in vergleichbaren Swipe-Apps. Es wird auch
 * kein zweites Mal geschrieben (idempotent über eine Transaktion).
 *
 * @param {{
 *   firestore: FirebaseFirestore.Firestore,
 *   groupId: string,
 *   movieId: number,
 * }} params
 * @returns {Promise<{matched: boolean, likeCount: number, memberCount: number}>}
 */
async function evaluateMatch({ firestore, groupId, movieId }) {
  if (typeof groupId !== 'string' || groupId.trim().length === 0) {
    throw new Error('evaluateMatch: ungültige groupId');
  }
  if (typeof movieId !== 'number' || !Number.isFinite(movieId)) {
    throw new Error('evaluateMatch: ungültige movieId');
  }

  const groupRef = firestore.collection('groups').doc(groupId);

  const groupSnap = await groupRef.get();
  if (!groupSnap.exists) {
    throw new Error(`evaluateMatch: Gruppe ${groupId} existiert nicht`);
  }

  const membersSnap = await groupRef.collection('members').get();
  const memberUids = membersSnap.docs.map((doc) => doc.id);
  const memberCount = memberUids.length;
  if (memberCount === 0) {
    // Gültiger, aber ungewöhnlicher Zustand (z. B. Momentaufnahme während
    // des Löschens) - kein Fehler, aber fachlich kann es kein Match geben.
    return { matched: false, likeCount: 0, memberCount: 0 };
  }

  const swipesSnap = await groupRef
    .collection('swipes')
    .where('movie_id', '==', movieId)
    .get();

  const decisionByUid = new Map();
  for (const doc of swipesSnap.docs) {
    const data = doc.data();
    if (typeof data.uid === 'string') {
      decisionByUid.set(data.uid, data.decision);
    }
  }

  // Absichtlich pro echtem Mitglied nachschlagen statt nur eine Like-Anzahl
  // zu zählen - ein Swipe eines Nicht-(mehr-)Mitglieds zählt so nie mit.
  const likeCount = memberUids.filter((uid) => decisionByUid.get(uid) === 'like').length;
  const isMatch = likeCount === memberCount;

  if (!isMatch) {
    return { matched: false, likeCount, memberCount };
  }

  const matchRef = groupRef.collection('matches').doc(String(movieId));
  await firestore.runTransaction(async (transaction) => {
    const existing = await transaction.get(matchRef);
    if (existing.exists) {
      // Bereits erzeugt - endgültiges Ergebnis, kein erneutes Schreiben, kein
      // zweites Dokument.
      return;
    }
    transaction.set(matchRef, {
      movie_id: movieId,
      // Momentaufnahme der Mitglieder, die den Match ausmachen - sortiert
      // für deterministische, diff-freundliche Vergleiche in Tests.
      member_uids: [...memberUids].sort(),
      matched_at: new Date(),
    });
  });

  return { matched: true, likeCount, memberCount };
}

module.exports = { evaluateMatch };
