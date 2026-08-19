import { readFileSync } from 'node:fs';
import { after, before, describe, it } from 'node:test';
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';

// Testet die tatsächliche storage.rules-Datei des Repos gegen den echten
// lokalen Firebase-Storage-Emulator. Deckt Abschnitt 18 der Schritt-3.1-
// Anforderungen ab.

let testEnv;

const smallJpeg = () => Uint8Array.from(Buffer.from('a'.repeat(1024)));

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'film2watch-rules-test',
    storage: {
      rules: readFileSync('../storage.rules', 'utf8'),
      host: '127.0.0.1',
      port: 9199,
    },
  });
});

after(async () => {
  await testEnv.cleanup();
});

describe('profile_images/{uid}', () => {
  it('lehnt einen nicht authentifizierten Upload ab', async () => {
    const storage = testEnv.unauthenticatedContext().storage();
    await assertFails(
      storage
        .ref('profile_images/alice/profile.jpg')
        .put(smallJpeg(), { contentType: 'image/jpeg' }),
    );
  });

  it('erlaubt User A den Upload in den eigenen Pfad', async () => {
    const storage = testEnv.authenticatedContext('alice').storage();
    await assertSucceeds(
      storage
        .ref('profile_images/alice/profile.jpg')
        .put(smallJpeg(), { contentType: 'image/jpeg' }),
    );
  });

  it('lehnt den Upload von User A in den Pfad von User B ab', async () => {
    const storage = testEnv.authenticatedContext('alice').storage();
    await assertFails(
      storage
        .ref('profile_images/bob/profile.jpg')
        .put(smallJpeg(), { contentType: 'image/jpeg' }),
    );
  });

  it('lehnt einen Upload ab, der kein Bild ist', async () => {
    const storage = testEnv.authenticatedContext('alice').storage();
    await assertFails(
      storage
        .ref('profile_images/alice/profile.jpg')
        .put(smallJpeg(), { contentType: 'text/plain' }),
    );
  });

  it('erlaubt User A, das eigene Bild zu löschen', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context
        .storage()
        .ref('profile_images/alice/profile.jpg')
        .put(smallJpeg(), { contentType: 'image/jpeg' });
    });

    const storage = testEnv.authenticatedContext('alice').storage();
    await assertSucceeds(storage.ref('profile_images/alice/profile.jpg').delete());
  });

  it('lehnt es ab, dass User A das Bild von User B löscht', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context
        .storage()
        .ref('profile_images/bob/profile.jpg')
        .put(smallJpeg(), { contentType: 'image/jpeg' });
    });

    const storage = testEnv.authenticatedContext('alice').storage();
    await assertFails(storage.ref('profile_images/bob/profile.jpg').delete());
  });
});
