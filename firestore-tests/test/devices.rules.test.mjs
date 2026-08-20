import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { after, before, describe, it } from 'node:test';
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';
import firebase from 'firebase/compat/app';
import 'firebase/compat/firestore';

// Testet die tatsächliche firestore.rules-Datei des Repos gegen den echten
// lokalen Firestore-Emulator für FCM-Geräte-Tokens (Schritt 9,
// `users/{uid}/devices/{token}`). Eigene User-IDs mit Zeitstempel-Suffix,
// um Überschneidungen mit anderen, parallel laufenden Test-Dateien zu
// vermeiden.

const serverTimestamp = () => firebase.firestore.FieldValue.serverTimestamp();

let testEnv;
const now = () => new Date();
const suffix = Date.now();
const alice = `alice-devices-${suffix}`;
const bob = `bob-devices-${suffix}`;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'film2watch-rules-test',
    firestore: {
      rules: readFileSync('../firestore.rules', 'utf8'),
      host: '127.0.0.1',
      port: 8080,
    },
  });

  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await db.doc(`users/${alice}/devices/existing-token`).set({
      token: 'existing-token',
      platform: 'android',
      created_at: now(),
      updated_at: now(),
    });
  });
});

after(async () => {
  await testEnv.cleanup();
});

describe('users/{uid}/devices/{deviceId}', () => {
  it('lehnt unauthentifiziertes Lesen ab', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(db.doc(`users/${alice}/devices/existing-token`).get());
  });

  it('lehnt unauthentifiziertes Erstellen ab', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(
      db.doc(`users/${alice}/devices/ghost-token`).set({
        token: 'ghost-token',
        platform: 'android',
        created_at: serverTimestamp(),
        updated_at: serverTimestamp(),
      }),
    );
  });

  it('User A kann einen eigenen Device-Eintrag erstellen', async () => {
    const db = testEnv.authenticatedContext(alice).firestore();
    await assertSucceeds(
      db.doc(`users/${alice}/devices/new-token`).set({
        token: 'new-token',
        platform: 'ios',
        created_at: serverTimestamp(),
        updated_at: serverTimestamp(),
      }),
    );
  });

  it('User A kann den eigenen Device-Eintrag aktualisieren', async () => {
    const db = testEnv.authenticatedContext(alice).firestore();
    await assertSucceeds(
      db.doc(`users/${alice}/devices/existing-token`).update({
        platform: 'ios',
        updated_at: serverTimestamp(),
      }),
    );
  });

  it('User A kann den eigenen Device-Eintrag lesen', async () => {
    const db = testEnv.authenticatedContext(alice).firestore();
    await assertSucceeds(db.doc(`users/${alice}/devices/existing-token`).get());
  });

  it('User A kann den eigenen Device-Eintrag löschen', async () => {
    const db = testEnv.authenticatedContext(alice).firestore();
    await assertSucceeds(
      db.doc(`users/${alice}/devices/to-delete`).set({
        token: 'to-delete',
        platform: 'android',
        created_at: serverTimestamp(),
        updated_at: serverTimestamp(),
      }),
    );
    await assertSucceeds(db.doc(`users/${alice}/devices/to-delete`).delete());
  });

  it('User B kann das Device von User A nicht lesen', async () => {
    const db = testEnv.authenticatedContext(bob).firestore();
    await assertFails(db.doc(`users/${alice}/devices/existing-token`).get());
  });

  it('User B kann kein Device für User A anlegen', async () => {
    const db = testEnv.authenticatedContext(bob).firestore();
    await assertFails(
      db.doc(`users/${alice}/devices/fremd-token`).set({
        token: 'fremd-token',
        platform: 'android',
        created_at: serverTimestamp(),
        updated_at: serverTimestamp(),
      }),
    );
  });

  it('User B kann das Device von User A nicht ändern', async () => {
    const db = testEnv.authenticatedContext(bob).firestore();
    await assertFails(
      db.doc(`users/${alice}/devices/existing-token`).update({ platform: 'ios' }),
    );
  });

  it('User B kann das Device von User A nicht löschen', async () => {
    const db = testEnv.authenticatedContext(bob).firestore();
    await assertFails(db.doc(`users/${alice}/devices/existing-token`).delete());
  });

  it('lehnt eine Dokument-ID ab, die nicht dem Token entspricht', async () => {
    const db = testEnv.authenticatedContext(alice).firestore();
    await assertFails(
      db.doc(`users/${alice}/devices/mismatched-id`).set({
        token: 'anderer-wert',
        platform: 'android',
        created_at: serverTimestamp(),
        updated_at: serverTimestamp(),
      }),
    );
  });

  it('lehnt einen client-gesetzten created_at-Wert ab', async () => {
    const db = testEnv.authenticatedContext(alice).firestore();
    await assertFails(
      db.doc(`users/${alice}/devices/fake-timestamp`).set({
        token: 'fake-timestamp',
        platform: 'android',
        created_at: new Date('2020-01-01'),
        updated_at: serverTimestamp(),
      }),
    );
  });

  it('lehnt eine ungültige platform ab', async () => {
    const db = testEnv.authenticatedContext(alice).firestore();
    await assertFails(
      db.doc(`users/${alice}/devices/bad-platform`).set({
        token: 'bad-platform',
        platform: 'windows',
        created_at: serverTimestamp(),
        updated_at: serverTimestamp(),
      }),
    );
  });
});
