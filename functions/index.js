'use strict';

const functions = require('firebase-functions/v1');
const admin = require('firebase-admin');
const { evaluateMatch } = require('./matchEngine');

admin.initializeApp();

/**
 * Firestore-Trigger auf jede Änderung eines Swipes (Anlegen einer neuen
 * Like/Dislike-Entscheidung oder Ändern einer bestehenden). Wertet nach
 * jeder Änderung serverseitig aus, ob der betroffene Film in dieser Gruppe
 * jetzt ein Match ist - siehe `matchEngine.js` für die eigentliche Regel.
 *
 * Bewusst 1st-Gen-Trigger (direkter Cloud-Firestore-Trigger statt Eventarc):
 * einfacher lokal mit dem Firebase Emulator zu betreiben, ohne zusätzliche
 * Pub/Sub-/Eventarc-Emulation.
 */
exports.onSwipeWritten = functions.firestore
  .document('groups/{groupId}/swipes/{swipeId}')
  .onWrite(async (change, context) => {
    const data = change.after.exists ? change.after.data() : change.before.data();
    if (!data) return null;

    const movieId = typeof data.movie_id === 'number' ? data.movie_id : Number(data.movie_id);
    if (Number.isNaN(movieId)) return null;

    try {
      await evaluateMatch({
        firestore: admin.firestore(),
        groupId: context.params.groupId,
        movieId,
      });
    } catch (error) {
      // Ein einzelner unerwarteter Zustand (z. B. Gruppe wurde zwischen
      // Trigger und Auswertung gelöscht) darf die Function nicht in einer
      // Retry-Schleife hängen lassen - loggen und sauber beenden.
      functions.logger.error('Match-Auswertung fehlgeschlagen', {
        groupId: context.params.groupId,
        swipeId: context.params.swipeId,
        error: error.message,
      });
    }
    return null;
  });
