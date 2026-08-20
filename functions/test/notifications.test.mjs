import assert from 'node:assert/strict';
import { before, beforeEach, describe, it } from 'node:test';
import admin from 'firebase-admin';
import { sendToUsers, claimNotification } from '../notifications.js';
import { notifyFriendRequest } from '../notifyFriendRequest.js';
import { notifyGroupInvitation } from '../notifyGroupInvitation.js';
import { notifyMatch } from '../notifyMatch.js';
import { notifyChatMessage } from '../notifyChatMessage.js';
import { postMatchChatMessage } from '../postMatchChatMessage.js';

// Testet die reine Notification-Logik (Empfänger-Ermittlung, Ausschluss des
// Absenders, Duplikat-Schutz, Cleanup ungültiger Tokens) gegen den echten
// Firestore-Emulator. Der tatsächliche FCM-Versand wird bewusst NICHT real
// ausgeführt - es gibt keinen "Firebase Cloud Messaging Emulator" und ohne
// echte Gerätetokens/Google-Cloud-Credentials in dieser Sandbox wäre ein
// echter Versand ohnehin nicht sinnvoll testbar. Stattdessen wird ein
// injizierter Fake-Messaging-Client verwendet (Dependency Injection, exakt
// wie schon bei `evaluateMatch`/`firestore` in matchEngine.test.mjs) - so
// wird die eigentliche, echte Logik geprüft, ohne einen Push vorzutäuschen.

const PROJECT_ID = process.env.GCLOUD_PROJECT || 'film2watch-rules-test';

let db;

before(() => {
  if (admin.apps.length === 0) {
    admin.initializeApp({ projectId: PROJECT_ID });
  }
  db = admin.firestore();
});

const now = () => new Date();

class FakeMessaging {
  constructor({ failingTokens = [] } = {}) {
    this.sentMessages = [];
    this.failingTokens = new Set(failingTokens);
  }

  async sendEachForMulticast({ tokens, notification, data }) {
    const responses = tokens.map((token) =>
      this.failingTokens.has(token)
        ? { success: false, error: { code: 'messaging/registration-token-not-registered' } }
        : { success: true },
    );
    this.sentMessages.push({ tokens, notification, data });
    return {
      successCount: responses.filter((r) => r.success).length,
      failureCount: responses.filter((r) => !r.success).length,
      responses,
    };
  }
}

async function addDevice(uid, token, { platform = 'android' } = {}) {
  await db.doc(`users/${uid}/devices/${token}`).set({
    token,
    platform,
    created_at: now(),
    updated_at: now(),
  });
}

function recipientTokens(messaging) {
  return messaging.sentMessages.flatMap((m) => m.tokens);
}

describe('Push-Notification-Logik', () => {
  describe('sendToUsers', () => {
    it('lädt Tokens mehrerer Geräte eines Users und versendet an alle', async () => {
      const uid = `sendtest-multi-${Date.now()}`;
      await addDevice(uid, `${uid}-tok1`);
      await addDevice(uid, `${uid}-tok2`);
      const messaging = new FakeMessaging();

      const result = await sendToUsers({
        firestore: db,
        messaging,
        uids: [uid],
        notification: { title: 't', body: 'b' },
        data: { type: 'x' },
      });

      assert.equal(result.sentCount, 2);
      assert.deepEqual(recipientTokens(messaging).sort(), [`${uid}-tok1`, `${uid}-tok2`].sort());
    });

    it('entfernt Tokens, die FCM als ungültig meldet', async () => {
      const uid = `sendtest-invalid-${Date.now()}`;
      await addDevice(uid, `${uid}-valid`);
      await addDevice(uid, `${uid}-dead`);
      const messaging = new FakeMessaging({ failingTokens: [`${uid}-dead`] });

      await sendToUsers({
        firestore: db,
        messaging,
        uids: [uid],
        notification: { title: 't', body: 'b' },
        data: { type: 'x' },
      });

      const remaining = await db.collection(`users/${uid}/devices`).get();
      assert.deepEqual(remaining.docs.map((d) => d.id), [`${uid}-valid`]);
    });

    it('ohne registrierte Geräte wird nichts versendet', async () => {
      const messaging = new FakeMessaging();
      const result = await sendToUsers({
        firestore: db,
        messaging,
        uids: [`no-devices-${Date.now()}`],
        notification: { title: 't', body: 'b' },
        data: {},
      });
      assert.equal(result.sentCount, 0);
      assert.equal(messaging.sentMessages.length, 0);
    });
  });

  describe('notifyFriendRequest', () => {
    it('der Empfänger bekommt eine Notification', async () => {
      const fromUid = `alice-${Date.now()}`;
      const toUid = `bob-${Date.now()}`;
      await db.doc(`public_profiles/${fromUid}`).set({ uid: fromUid, name: 'Alice', friend_code: 'X', profile_picture: null });
      await addDevice(toUid, `${toUid}-tok`);
      const requestId = `${fromUid}_${toUid}`;
      await db.doc(`friend_requests/${requestId}`).set({ fromUid, toUid, createdAt: now() });
      const messaging = new FakeMessaging();

      await notifyFriendRequest({ firestore: db, messaging, requestId, fromUid, toUid });

      assert.equal(messaging.sentMessages.length, 1);
      assert.deepEqual(messaging.sentMessages[0].tokens, [`${toUid}-tok`]);
      assert.match(messaging.sentMessages[0].notification.body, /Alice/);
    });

    it('der Absender bekommt keine eigene Notification', async () => {
      const fromUid = `alice2-${Date.now()}`;
      const toUid = `bob2-${Date.now()}`;
      await addDevice(fromUid, `${fromUid}-tok`);
      await addDevice(toUid, `${toUid}-tok`);
      const requestId = `${fromUid}_${toUid}`;
      await db.doc(`friend_requests/${requestId}`).set({ fromUid, toUid, createdAt: now() });
      const messaging = new FakeMessaging();

      await notifyFriendRequest({ firestore: db, messaging, requestId, fromUid, toUid });

      assert.deepEqual(recipientTokens(messaging), [`${toUid}-tok`]);
    });
  });

  describe('notifyGroupInvitation', () => {
    it('die eingeladene Person bekommt eine Notification, sonst niemand', async () => {
      const groupId = `group-${Date.now()}`;
      const inviterUid = `inviter-${Date.now()}`;
      const inviteeUid = `invitee-${Date.now()}`;
      await db.doc(`groups/${groupId}`).set({ id: groupId, name: 'Filmabend', created_by: inviterUid, created_at: now(), updated_at: now() });
      await addDevice(inviterUid, `${inviterUid}-tok`);
      await addDevice(inviteeUid, `${inviteeUid}-tok`);
      const invitationId = `${groupId}_${inviteeUid}`;
      await db.doc(`group_invitations/${invitationId}`).set({ groupId, inviterUid, inviteeUid, createdAt: now() });
      const messaging = new FakeMessaging();

      await notifyGroupInvitation({ firestore: db, messaging, invitationId, groupId, inviteeUid });

      assert.deepEqual(recipientTokens(messaging), [`${inviteeUid}-tok`]);
      assert.match(messaging.sentMessages[0].notification.body, /Filmabend/);
    });
  });

  describe('notifyMatch', () => {
    it('alle aktuellen Mitglieder bekommen eine Notification', async () => {
      const groupId = `matchgroup-${Date.now()}`;
      const alice = `alice-${Date.now()}`;
      const bob = `bob-${Date.now()}`;
      await db.doc(`groups/${groupId}`).set({ id: groupId, name: 'Filmabend', created_by: alice, created_at: now(), updated_at: now() });
      await db.doc(`groups/${groupId}/members/${alice}`).set({ uid: alice, role: 'admin', joined_at: now() });
      await db.doc(`groups/${groupId}/members/${bob}`).set({ uid: bob, role: 'member', joined_at: now() });
      await addDevice(alice, `${alice}-tok`);
      await addDevice(bob, `${bob}-tok`);
      const matchRef = db.doc(`groups/${groupId}/matches/550`);
      await matchRef.set({ movie_id: 550, member_uids: [alice, bob].sort(), matched_at: now() });
      const messaging = new FakeMessaging();

      await notifyMatch({ firestore: db, messaging, groupId, matchRef });

      assert.deepEqual(recipientTokens(messaging).sort(), [`${alice}-tok`, `${bob}-tok`].sort());
    });

    it('ein erneuter Aufruf für dasselbe Match verschickt keine zweite Notification (Duplikatschutz)', async () => {
      const groupId = `matchgroup2-${Date.now()}`;
      const alice = `alice-${Date.now()}`;
      await db.doc(`groups/${groupId}`).set({ id: groupId, name: 'Filmabend', created_by: alice, created_at: now(), updated_at: now() });
      await db.doc(`groups/${groupId}/members/${alice}`).set({ uid: alice, role: 'admin', joined_at: now() });
      await addDevice(alice, `${alice}-tok`);
      const matchRef = db.doc(`groups/${groupId}/matches/551`);
      await matchRef.set({ movie_id: 551, member_uids: [alice], matched_at: now() });
      const messaging = new FakeMessaging();

      await notifyMatch({ firestore: db, messaging, groupId, matchRef });
      await notifyMatch({ firestore: db, messaging, groupId, matchRef });

      assert.equal(messaging.sentMessages.length, 1);
    });
  });

  describe('notifyChatMessage', () => {
    let groupId, alice, bob, carol;

    beforeEach(async () => {
      const suffix = Date.now();
      groupId = `chatgroup-${suffix}`;
      alice = `alice-${suffix}`;
      bob = `bob-${suffix}`;
      carol = `carol-${suffix}`;
      await db.doc(`groups/${groupId}`).set({ id: groupId, name: 'Filmabend', created_by: alice, created_at: now(), updated_at: now() });
      await db.doc(`groups/${groupId}/members/${alice}`).set({ uid: alice, role: 'admin', joined_at: now() });
      await db.doc(`groups/${groupId}/members/${bob}`).set({ uid: bob, role: 'member', joined_at: now() });
      await db.doc(`public_profiles/${alice}`).set({ uid: alice, name: 'Alice', friend_code: 'X', profile_picture: null });
      await addDevice(alice, `${alice}-tok`);
      await addDevice(bob, `${bob}-tok`);
      // carol ist kein Mitglied dieser Gruppe.
      await addDevice(carol, `${carol}-tok`);
    });

    it('andere Gruppenmitglieder bekommen eine Notification', async () => {
      const messageRef = db.doc(`groups/${groupId}/messages/msg1`);
      await messageRef.set({ sender_uid: alice, text: 'Hallo zusammen!', created_at: now() });
      const messaging = new FakeMessaging();

      await notifyChatMessage({ firestore: db, messaging, groupId, messageRef, senderUid: alice, text: 'Hallo zusammen!' });

      assert.deepEqual(recipientTokens(messaging), [`${bob}-tok`]);
    });

    it('der Absender bekommt keine eigene Notification', async () => {
      const messageRef = db.doc(`groups/${groupId}/messages/msg2`);
      await messageRef.set({ sender_uid: alice, text: 'Test', created_at: now() });
      const messaging = new FakeMessaging();

      await notifyChatMessage({ firestore: db, messaging, groupId, messageRef, senderUid: alice, text: 'Test' });

      assert.ok(!recipientTokens(messaging).includes(`${alice}-tok`));
    });

    it('Nicht-Mitglieder bekommen nichts', async () => {
      const messageRef = db.doc(`groups/${groupId}/messages/msg3`);
      await messageRef.set({ sender_uid: alice, text: 'Test', created_at: now() });
      const messaging = new FakeMessaging();

      await notifyChatMessage({ firestore: db, messaging, groupId, messageRef, senderUid: alice, text: 'Test' });

      assert.ok(!recipientTokens(messaging).includes(`${carol}-tok`));
    });

    it('lange Nachrichten werden in der Vorschau gekürzt', async () => {
      const longText = 'x'.repeat(200);
      const messageRef = db.doc(`groups/${groupId}/messages/msg4`);
      await messageRef.set({ sender_uid: alice, text: longText, created_at: now() });
      const messaging = new FakeMessaging();

      await notifyChatMessage({ firestore: db, messaging, groupId, messageRef, senderUid: alice, text: longText });

      const body = messaging.sentMessages[0].notification.body;
      assert.ok(body.length < longText.length);
    });
  });

  describe('claimNotification', () => {
    it('beansprucht ein Dokument nur einmal', async () => {
      const ref = db.doc(`groups/claimtest-${Date.now()}/matches/1`);
      await ref.set({ movie_id: 1, member_uids: ['alice'], matched_at: now() });

      const first = await claimNotification({ firestore: db, ref });
      const second = await claimNotification({ firestore: db, ref });

      assert.equal(first, true);
      assert.equal(second, false);
    });

    it('erlaubt unabhängige Claims auf demselben Dokument über verschiedene Felder', async () => {
      const ref = db.doc(`groups/claimtest2-${Date.now()}/matches/1`);
      await ref.set({ movie_id: 1, member_uids: ['alice'], matched_at: now() });

      const pushClaimed = await claimNotification({ firestore: db, ref, field: 'notified_at' });
      const chatClaimed = await claimNotification({ firestore: db, ref, field: 'chat_message_posted_at' });
      // Ein zweiter Versuch auf demselben Feld bleibt weiterhin blockiert.
      const pushClaimedAgain = await claimNotification({ firestore: db, ref, field: 'notified_at' });

      assert.equal(pushClaimed, true);
      assert.equal(chatClaimed, true);
      assert.equal(pushClaimedAgain, false);
    });
  });

  describe('postMatchChatMessage', () => {
    it('postet eine Systemnachricht mit der movie_id in den Gruppenchat', async () => {
      const groupId = `matchchat-${Date.now()}`;
      const matchRef = db.doc(`groups/${groupId}/matches/550`);
      await matchRef.set({ movie_id: 550, member_uids: ['alice'], matched_at: now() });

      await postMatchChatMessage({ firestore: db, groupId, matchRef, movieId: 550 });

      const messages = await db.collection(`groups/${groupId}/messages`).get();
      assert.equal(messages.size, 1);
      const data = messages.docs[0].data();
      assert.equal(data.type, 'match');
      assert.equal(data.movie_id, 550);
      assert.equal(data.sender_uid, undefined);
      assert.equal(data.text, undefined);
    });

    it('ein erneuter Aufruf für dasselbe Match postet keine zweite Systemnachricht (Duplikatschutz)', async () => {
      const groupId = `matchchat2-${Date.now()}`;
      const matchRef = db.doc(`groups/${groupId}/matches/551`);
      await matchRef.set({ movie_id: 551, member_uids: ['alice'], matched_at: now() });

      await postMatchChatMessage({ firestore: db, groupId, matchRef, movieId: 551 });
      await postMatchChatMessage({ firestore: db, groupId, matchRef, movieId: 551 });

      const messages = await db.collection(`groups/${groupId}/messages`).get();
      assert.equal(messages.size, 1);
    });

    it('nutzt einen eigenen Idempotenz-Marker, unabhängig vom Push-Duplikatschutz von notifyMatch', async () => {
      const groupId = `matchchat3-${Date.now()}`;
      const alice = `alice-${Date.now()}`;
      await db.doc(`groups/${groupId}`).set({ id: groupId, name: 'Filmabend', created_by: alice, created_at: now(), updated_at: now() });
      await db.doc(`groups/${groupId}/members/${alice}`).set({ uid: alice, role: 'admin', joined_at: now() });
      await addDevice(alice, `${alice}-tok`);
      const matchRef = db.doc(`groups/${groupId}/matches/552`);
      await matchRef.set({ movie_id: 552, member_uids: [alice], matched_at: now() });
      const messaging = new FakeMessaging();

      // notifyMatch beansprucht `notified_at` - darf postMatchChatMessage
      // (eigenes Feld `chat_message_posted_at`) nicht blockieren, und
      // umgekehrt.
      await notifyMatch({ firestore: db, messaging, groupId, matchRef });
      await postMatchChatMessage({ firestore: db, groupId, matchRef, movieId: 552 });

      assert.equal(messaging.sentMessages.length, 1);
      const messages = await db.collection(`groups/${groupId}/messages`).get();
      assert.equal(messages.size, 1);
    });
  });
});
