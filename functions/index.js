'use strict';

const functions = require('firebase-functions/v1');
const admin = require('firebase-admin');
const { evaluateMatch } = require('./matchEngine');
const { updateUserGenrePreferences } = require('./userPreferences');
const { notifyFriendRequest } = require('./notifyFriendRequest');
const { notifyGroupInvitation } = require('./notifyGroupInvitation');
const { notifyMatch } = require('./notifyMatch');
const { notifyChatMessage } = require('./notifyChatMessage');
const { notifyMovieNightCreated } = require('./notifyMovieNightCreated');
const { postMatchChatMessage } = require('./postMatchChatMessage');

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

/**
 * Zweiter, unabhängiger Trigger auf denselben Swipe-Schreibvorgang wie
 * `onSwipeWritten` (Firestore erlaubt mehrere Functions auf demselben
 * Dokumentpfad) - hält `user_preferences/{uid}` aktuell (§7/§18/§17.4:
 * Genre-Präferenz/Anti-Boost). Eigene Function statt in `onSwipeWritten`
 * verschachtelt, analog zur bestehenden Trennung von Match-Erkennung
 * (`matchEngine.js`) und Notifications - jede Function hat genau eine
 * Zuständigkeit. Reagiert auch auf Löschen (z. B. Watchlist-Entfernen) und
 * Ändern einer Entscheidung, da `updateUserGenrePreferences` die komplette
 * Historie neu auswertet statt einen Zähler zu inkrementieren.
 */
exports.onSwipeWrittenForPreferences = functions.firestore
  .document('groups/{groupId}/swipes/{swipeId}')
  .onWrite(async (change, context) => {
    const data = change.after.exists ? change.after.data() : change.before.data();
    if (!data || typeof data.uid !== 'string') return null;

    try {
      await updateUserGenrePreferences({ firestore: admin.firestore(), uid: data.uid });
    } catch (error) {
      functions.logger.error('Genre-Präferenz-Aktualisierung fehlgeschlagen', {
        groupId: context.params.groupId,
        swipeId: context.params.swipeId,
        uid: data.uid,
        error: error.message,
      });
    }
    return null;
  });

/**
 * Push-Notifications: reine Empfänger-Ermittlung + Versand, verändern nie
 * das ursprüngliche Firestore-Dokument (außer dem eigenen `notified_at`-
 * Idempotenz-Marker, siehe `notifications.js`). Ein Fehlschlag beim Senden
 * lässt den jeweiligen Firestore-Hauptvorgang (Anfrage/Einladung/Match/
 * Nachricht) unangetastet - der ist zu diesem Zeitpunkt bereits
 * abgeschlossen, diese Trigger laufen unabhängig danach.
 */
exports.onFriendRequestCreated = functions.firestore
  .document('friend_requests/{requestId}')
  .onCreate(async (snapshot, context) => {
    try {
      const data = snapshot.data();
      await notifyFriendRequest({
        firestore: admin.firestore(),
        messaging: admin.messaging(),
        requestId: context.params.requestId,
        fromUid: data.fromUid,
        toUid: data.toUid,
      });
    } catch (error) {
      functions.logger.error('Freundschaftsanfrage-Notification fehlgeschlagen', {
        requestId: context.params.requestId,
        error: error.message,
      });
    }
    return null;
  });

exports.onGroupInvitationCreated = functions.firestore
  .document('group_invitations/{invitationId}')
  .onCreate(async (snapshot, context) => {
    try {
      const data = snapshot.data();
      await notifyGroupInvitation({
        firestore: admin.firestore(),
        messaging: admin.messaging(),
        invitationId: context.params.invitationId,
        groupId: data.groupId,
        inviteeUid: data.inviteeUid,
      });
    } catch (error) {
      functions.logger.error('Gruppeneinladungs-Notification fehlgeschlagen', {
        invitationId: context.params.invitationId,
        error: error.message,
      });
    }
    return null;
  });

exports.onMatchCreated = functions.firestore
  .document('groups/{groupId}/matches/{matchId}')
  .onCreate(async (snapshot, context) => {
    try {
      await notifyMatch({
        firestore: admin.firestore(),
        messaging: admin.messaging(),
        groupId: context.params.groupId,
        matchRef: snapshot.ref,
      });
    } catch (error) {
      functions.logger.error('Match-Notification fehlgeschlagen', {
        groupId: context.params.groupId,
        matchId: context.params.matchId,
        error: error.message,
      });
    }

    // Eigener try/catch: das Posten der Chat-Systemnachricht darf
    // unabhängig vom Push-Versand fehlschlagen oder gelingen (getrennte
    // Idempotenz-Felder auf demselben Match-Dokument, siehe
    // `postMatchChatMessage.js`).
    try {
      const data = snapshot.data();
      const movieId = typeof data.movie_id === 'number' ? data.movie_id : Number(data.movie_id);
      if (!Number.isNaN(movieId)) {
        await postMatchChatMessage({
          firestore: admin.firestore(),
          groupId: context.params.groupId,
          matchRef: snapshot.ref,
          movieId,
        });
      }
    } catch (error) {
      functions.logger.error('Match-Chatnachricht fehlgeschlagen', {
        groupId: context.params.groupId,
        matchId: context.params.matchId,
        error: error.message,
      });
    }
    return null;
  });

exports.onChatMessageCreated = functions.firestore
  .document('groups/{groupId}/messages/{messageId}')
  .onCreate(async (snapshot, context) => {
    try {
      const data = snapshot.data();
      await notifyChatMessage({
        firestore: admin.firestore(),
        messaging: admin.messaging(),
        groupId: context.params.groupId,
        messageRef: snapshot.ref,
        senderUid: data.sender_uid,
        text: typeof data.text === 'string' ? data.text : '',
      });
    } catch (error) {
      functions.logger.error('Chat-Notification fehlgeschlagen', {
        groupId: context.params.groupId,
        messageId: context.params.messageId,
        error: error.message,
      });
    }
    return null;
  });

/**
 * Reminder-Push bei der Erstellung eines Filmabends (§12: "Filmabend
 * planen"). Nur die Erstellung ist ein Notification-Ereignis - ein
 * nachträgliches Bearbeiten oder Absagen löst bewusst keinen weiteren Push
 * aus (mit dem Produktverantwortlichen abgestimmt, kein zeitgesteuerter
 * Reminder, siehe `notifyMovieNightCreated.js`).
 */
exports.onMovieNightCreated = functions.firestore
  .document('groups/{groupId}/movie_nights/{movieNightId}')
  .onCreate(async (snapshot, context) => {
    try {
      const data = snapshot.data();
      await notifyMovieNightCreated({
        firestore: admin.firestore(),
        messaging: admin.messaging(),
        groupId: context.params.groupId,
        movieNightRef: snapshot.ref,
        createdBy: data.created_by,
      });
    } catch (error) {
      functions.logger.error('Filmabend-Notification fehlgeschlagen', {
        groupId: context.params.groupId,
        movieNightId: context.params.movieNightId,
        error: error.message,
      });
    }
    return null;
  });
