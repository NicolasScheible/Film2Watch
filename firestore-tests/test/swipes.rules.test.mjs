import { readFileSync } from 'node:fs';
import { after, before, describe, it } from 'node:test';
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';

// Testet die tatsächliche firestore.rules-Datei des Repos gegen den echten
// lokalen Firestore-Emulator für die Gruppen-Swipe-Funktion (Schritt 6).

let testEnv;
const now = () => new Date();

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
    await db.doc('groups/swipesgroup1').set({
      id: 'swipesgroup1',
      name: 'Filmabend',
      photo_url: null,
      created_by: 'alice',
      created_at: now(),
      updated_at: now(),
    });
    await db.doc('groups/swipesgroup1/members/alice').set({ uid: 'alice', role: 'admin', joined_at: now() });
    await db.doc('groups/swipesgroup1/members/bob').set({ uid: 'bob', role: 'member', joined_at: now() });
    // carol ist kein Mitglied von swipesgroup1.
    await db.doc('groups/swipesgroup1/swipes/alice_100').set({
      uid: 'alice',
      movie_id: 100,
      decision: 'like',
      created_at: now(),
      updated_at: now(),
    });
    await db.doc('groups/swipesgroup1/swipes/bob_200').set({
      uid: 'bob',
      movie_id: 200,
      decision: 'dislike',
      created_at: now(),
      updated_at: now(),
    });
    // alice ist Premium, bob nicht - Grundlage für die Super-Swipe-Tests
    // (§6/§15). bob bleibt bewusst ohne premium_status-Dokument (Normalfall
    // für einen Free-User).
    await db.doc('premium_status/alice').set({ is_premium: true });
  });
});

after(async () => {
  await testEnv.cleanup();
});

describe('groups/{groupId}/swipes/{swipeId}', () => {
  it('lehnt unauthentifiziertes Lesen ab', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(db.doc('groups/swipesgroup1/swipes/alice_100').get());
  });

  it('lehnt unauthentifiziertes Schreiben ab', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(
      db.doc('groups/swipesgroup1/swipes/alice_999').set({
        uid: 'alice',
        movie_id: 999,
        decision: 'like',
        created_at: now(),
        updated_at: now(),
      }),
    );
  });

  it('erlaubt einem Mitglied, den eigenen Swipe anzulegen (like)', async () => {
    const db = testEnv.authenticatedContext('bob').firestore();
    await assertSucceeds(
      db.doc('groups/swipesgroup1/swipes/bob_300').set({
        uid: 'bob',
        movie_id: 300,
        decision: 'like',
        created_at: now(),
        updated_at: now(),
      }),
    );
  });

  it('erlaubt einem Mitglied, den eigenen Swipe anzulegen (dislike)', async () => {
    const db = testEnv.authenticatedContext('bob').firestore();
    await assertSucceeds(
      db.doc('groups/swipesgroup1/swipes/bob_301').set({
        uid: 'bob',
        movie_id: 301,
        decision: 'dislike',
        created_at: now(),
        updated_at: now(),
      }),
    );
  });

  it('erlaubt einem Mitglied, den eigenen Swipe anzulegen (skip)', async () => {
    const db = testEnv.authenticatedContext('bob').firestore();
    await assertSucceeds(
      db.doc('groups/swipesgroup1/swipes/bob_302').set({
        uid: 'bob',
        movie_id: 302,
        decision: 'skip',
        created_at: now(),
        updated_at: now(),
      }),
    );
  });

  it('lehnt es ab, dass ein fremder Nutzer einen Skip für ein anderes Mitglied anlegt', async () => {
    const db = testEnv.authenticatedContext('bob').firestore();
    await assertFails(
      db.doc('groups/swipesgroup1/swipes/alice_303').set({
        uid: 'alice',
        movie_id: 303,
        decision: 'skip',
        created_at: now(),
        updated_at: now(),
      }),
    );
  });

  it('erlaubt es dem User, den eigenen Swipe von like auf skip zu aktualisieren', async () => {
    const db = testEnv.authenticatedContext('alice').firestore();
    await assertSucceeds(
      db.doc('groups/swipesgroup1/swipes/alice_100').update({ decision: 'skip', updated_at: now() }),
    );
  });

  it('lehnt es ab, dass ein fremder Nutzer einen bestehenden Skip verändert', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().doc('groups/swipesgroup1/swipes/bob_304').set({
        uid: 'bob',
        movie_id: 304,
        decision: 'skip',
        created_at: now(),
        updated_at: now(),
      });
    });
    const db = testEnv.authenticatedContext('alice').firestore();
    await assertFails(
      db.doc('groups/swipesgroup1/swipes/bob_304').update({ decision: 'like', updated_at: now() }),
    );
  });

  it('erlaubt einem Mitglied, den eigenen Swipe anzulegen (watchlist)', async () => {
    const db = testEnv.authenticatedContext('bob').firestore();
    await assertSucceeds(
      db.doc('groups/swipesgroup1/swipes/bob_305').set({
        uid: 'bob',
        movie_id: 305,
        decision: 'watchlist',
        created_at: now(),
        updated_at: now(),
      }),
    );
  });

  it('lehnt es ab, dass ein fremder Nutzer eine Watchlist-Entscheidung für ein anderes Mitglied anlegt', async () => {
    const db = testEnv.authenticatedContext('bob').firestore();
    await assertFails(
      db.doc('groups/swipesgroup1/swipes/alice_306').set({
        uid: 'alice',
        movie_id: 306,
        decision: 'watchlist',
        created_at: now(),
        updated_at: now(),
      }),
    );
  });

  it('erlaubt es dem User, den eigenen Swipe von like auf watchlist zu aktualisieren', async () => {
    const db = testEnv.authenticatedContext('alice').firestore();
    await assertSucceeds(
      db.doc('groups/swipesgroup1/swipes/alice_100').update({ decision: 'watchlist', updated_at: now() }),
    );
  });

  it('lehnt es ab, dass ein fremder Nutzer eine bestehende Watchlist-Entscheidung verändert', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().doc('groups/swipesgroup1/swipes/bob_307').set({
        uid: 'bob',
        movie_id: 307,
        decision: 'watchlist',
        created_at: now(),
        updated_at: now(),
      });
    });
    const db = testEnv.authenticatedContext('alice').firestore();
    await assertFails(
      db.doc('groups/swipesgroup1/swipes/bob_307').update({ decision: 'like', updated_at: now() }),
    );
  });

  it('erlaubt einem Mitglied das Lesen eines Swipes in der eigenen Gruppe', async () => {
    const db = testEnv.authenticatedContext('bob').firestore();
    await assertSucceeds(db.doc('groups/swipesgroup1/swipes/alice_100').get());
  });

  it('lehnt es ab, dass ein Mitglied den Swipe eines anderen Mitglieds anlegt', async () => {
    const db = testEnv.authenticatedContext('bob').firestore();
    await assertFails(
      db.doc('groups/swipesgroup1/swipes/alice_400').set({
        uid: 'alice',
        movie_id: 400,
        decision: 'like',
        created_at: now(),
        updated_at: now(),
      }),
    );
  });

  it('lehnt das Lesen durch ein Nicht-Mitglied ab', async () => {
    const db = testEnv.authenticatedContext('carol').firestore();
    await assertFails(db.doc('groups/swipesgroup1/swipes/alice_100').get());
  });

  it('lehnt das Schreiben durch ein Nicht-Mitglied ab', async () => {
    const db = testEnv.authenticatedContext('carol').firestore();
    await assertFails(
      db.doc('groups/swipesgroup1/swipes/carol_500').set({
        uid: 'carol',
        movie_id: 500,
        decision: 'like',
        created_at: now(),
        updated_at: now(),
      }),
    );
  });

  it('lehnt es ab, dass User A den Swipe von User B löscht', async () => {
    const db = testEnv.authenticatedContext('alice').firestore();
    await assertFails(db.doc('groups/swipesgroup1/swipes/bob_200').delete());
  });

  it('lehnt es ab, dass der eigene Dislike-Swipe gelöscht wird (nur Watchlist ist löschbar)', async () => {
    const db = testEnv.authenticatedContext('bob').firestore();
    await assertFails(db.doc('groups/swipesgroup1/swipes/bob_200').delete());
  });

  it('lehnt es ab, dass der eigene Like-Swipe gelöscht wird (nur Watchlist ist löschbar)', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().doc('groups/swipesgroup1/swipes/alice_799').set({
        uid: 'alice',
        movie_id: 799,
        decision: 'like',
        created_at: now(),
        updated_at: now(),
      });
    });
    const db = testEnv.authenticatedContext('alice').firestore();
    await assertFails(db.doc('groups/swipesgroup1/swipes/alice_799').delete());
  });

  it('lehnt es ab, dass der eigene Skip-Swipe gelöscht wird (nur Watchlist ist löschbar)', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().doc('groups/swipesgroup1/swipes/alice_800').set({
        uid: 'alice',
        movie_id: 800,
        decision: 'skip',
        created_at: now(),
        updated_at: now(),
      });
    });
    const db = testEnv.authenticatedContext('alice').firestore();
    await assertFails(db.doc('groups/swipesgroup1/swipes/alice_800').delete());
  });

  it('erlaubt es dem User, den eigenen Watchlist-Eintrag zu löschen (Watchlist entfernen)', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().doc('groups/swipesgroup1/swipes/alice_801').set({
        uid: 'alice',
        movie_id: 801,
        decision: 'watchlist',
        created_at: now(),
        updated_at: now(),
      });
    });
    const db = testEnv.authenticatedContext('alice').firestore();
    await assertSucceeds(db.doc('groups/swipesgroup1/swipes/alice_801').delete());
  });

  it('lehnt es ab, dass ein fremder Nutzer einen Watchlist-Eintrag eines anderen Mitglieds löscht', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().doc('groups/swipesgroup1/swipes/bob_802').set({
        uid: 'bob',
        movie_id: 802,
        decision: 'watchlist',
        created_at: now(),
        updated_at: now(),
      });
    });
    const db = testEnv.authenticatedContext('alice').firestore();
    await assertFails(db.doc('groups/swipesgroup1/swipes/bob_802').delete());
  });

  it('lehnt es ab, dass ein Nicht-Mitglied einen Watchlist-Eintrag löscht', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().doc('groups/swipesgroup1/swipes/bob_803').set({
        uid: 'bob',
        movie_id: 803,
        decision: 'watchlist',
        created_at: now(),
        updated_at: now(),
      });
    });
    // carol ist kein Mitglied dieser Gruppe.
    const db = testEnv.authenticatedContext('carol').firestore();
    await assertFails(db.doc('groups/swipesgroup1/swipes/bob_803').delete());
  });

  it('lehnt unauthentifiziertes Löschen eines Watchlist-Eintrags ab', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().doc('groups/swipesgroup1/swipes/alice_804').set({
        uid: 'alice',
        movie_id: 804,
        decision: 'watchlist',
        created_at: now(),
        updated_at: now(),
      });
    });
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(db.doc('groups/swipesgroup1/swipes/alice_804').delete());
  });

  it('erlaubt es dem User, den eigenen Swipe zu aktualisieren (Like -> Dislike)', async () => {
    const db = testEnv.authenticatedContext('alice').firestore();
    await assertSucceeds(
      db.doc('groups/swipesgroup1/swipes/alice_100').update({ decision: 'dislike', updated_at: now() }),
    );
  });

  it('lehnt es ab, dass beim Update uid oder movie_id verändert werden', async () => {
    const db = testEnv.authenticatedContext('bob').firestore();
    await assertFails(
      db.doc('groups/swipesgroup1/swipes/bob_200').update({ movie_id: 999, updated_at: now() }),
    );
  });

  it('lehnt eine ungültige decision beim Anlegen ab', async () => {
    const db = testEnv.authenticatedContext('bob').firestore();
    await assertFails(
      db.doc('groups/swipesgroup1/swipes/bob_600').set({
        uid: 'bob',
        movie_id: 600,
        decision: 'maybe',
        created_at: now(),
        updated_at: now(),
      }),
    );
  });

  it('lehnt eine Dokument-ID ab, die nicht dem Muster {uid}_{movieId} entspricht', async () => {
    const db = testEnv.authenticatedContext('bob').firestore();
    await assertFails(
      db.doc('groups/swipesgroup1/swipes/wrong_id').set({
        uid: 'bob',
        movie_id: 700,
        decision: 'like',
        created_at: now(),
        updated_at: now(),
      }),
    );
  });

  // §7/§18 Boost-Algorithmus: genre_ids (TMDB-Genre-IDs zum Zeitpunkt des
  // Swipes) sind optional, aber wenn vorhanden typgeprüft und nach dem
  // Anlegen unveränderlich - Grundlage für die serverseitige Genre-
  // Präferenz/Anti-Boost-Auswertung (functions/userPreferences.js).
  it('erlaubt einen Swipe mit genre_ids', async () => {
    const db = testEnv.authenticatedContext('bob').firestore();
    await assertSucceeds(
      db.doc('groups/swipesgroup1/swipes/bob_900').set({
        uid: 'bob',
        movie_id: 900,
        decision: 'like',
        genre_ids: [27, 878],
        created_at: now(),
        updated_at: now(),
      }),
    );
  });

  it('erlaubt einen Swipe weiterhin auch ohne genre_ids (Rückwärtskompatibilität)', async () => {
    const db = testEnv.authenticatedContext('bob').firestore();
    await assertSucceeds(
      db.doc('groups/swipesgroup1/swipes/bob_901').set({
        uid: 'bob',
        movie_id: 901,
        decision: 'like',
        created_at: now(),
        updated_at: now(),
      }),
    );
  });

  it('lehnt einen Swipe ab, dessen genre_ids kein Array ist', async () => {
    const db = testEnv.authenticatedContext('bob').firestore();
    await assertFails(
      db.doc('groups/swipesgroup1/swipes/bob_902').set({
        uid: 'bob',
        movie_id: 902,
        decision: 'like',
        genre_ids: 'action',
        created_at: now(),
        updated_at: now(),
      }),
    );
  });

  it('lehnt es ab, dass genre_ids beim Update nachträglich verändert wird', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().doc('groups/swipesgroup1/swipes/bob_903').set({
        uid: 'bob',
        movie_id: 903,
        decision: 'like',
        genre_ids: [27],
        created_at: now(),
        updated_at: now(),
      });
    });
    const db = testEnv.authenticatedContext('bob').firestore();
    await assertFails(
      db.doc('groups/swipesgroup1/swipes/bob_903').update({
        decision: 'dislike',
        genre_ids: [28],
        updated_at: now(),
      }),
    );
  });

  it('erlaubt ein Update, das genre_ids unverändert lässt', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().doc('groups/swipesgroup1/swipes/bob_904').set({
        uid: 'bob',
        movie_id: 904,
        decision: 'like',
        genre_ids: [27],
        created_at: now(),
        updated_at: now(),
      });
    });
    const db = testEnv.authenticatedContext('bob').firestore();
    await assertSucceeds(
      db.doc('groups/swipesgroup1/swipes/bob_904').update({
        decision: 'dislike',
        genre_ids: [27],
        updated_at: now(),
      }),
    );
  });

  // Super Swipe (§6/§15, Premium-Feature) - serverseitig über isPremium()
  // erzwungen, niemals nur clientseitig geprüft. alice ist laut Setup
  // Premium, bob nicht (siehe premium_status/{userId} weiter unten für die
  // Regeln des Dokuments selbst).
  it('erlaubt einem Premium-Mitglied, einen Super Swipe anzulegen', async () => {
    const db = testEnv.authenticatedContext('alice').firestore();
    await assertSucceeds(
      db.doc('groups/swipesgroup1/swipes/alice_910').set({
        uid: 'alice',
        movie_id: 910,
        decision: 'super',
        created_at: now(),
        updated_at: now(),
      }),
    );
  });

  it('lehnt einen Super Swipe von einem Nicht-Premium-Mitglied ab', async () => {
    const db = testEnv.authenticatedContext('bob').firestore();
    await assertFails(
      db.doc('groups/swipesgroup1/swipes/bob_911').set({
        uid: 'bob',
        movie_id: 911,
        decision: 'super',
        created_at: now(),
        updated_at: now(),
      }),
    );
  });

  it('lehnt es ab, dass ein Nicht-Mitglied trotz Premium einen Super Swipe anlegt', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().doc('premium_status/carol').set({ is_premium: true });
    });
    const db = testEnv.authenticatedContext('carol').firestore();
    await assertFails(
      db.doc('groups/swipesgroup1/swipes/carol_912').set({
        uid: 'carol',
        movie_id: 912,
        decision: 'super',
        created_at: now(),
        updated_at: now(),
      }),
    );
  });

  it('lehnt es ab, dass ein Nicht-Premium-Mitglied einen bestehenden Swipe zu einem Super Swipe aktualisiert', async () => {
    const db = testEnv.authenticatedContext('bob').firestore();
    await assertFails(
      db.doc('groups/swipesgroup1/swipes/bob_200').update({ decision: 'super', updated_at: now() }),
    );
  });

  it('erlaubt es einem Premium-Mitglied, einen bestehenden Swipe zu einem Super Swipe zu aktualisieren', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().doc('groups/swipesgroup1/swipes/alice_913').set({
        uid: 'alice',
        movie_id: 913,
        decision: 'like',
        created_at: now(),
        updated_at: now(),
      });
    });
    const db = testEnv.authenticatedContext('alice').firestore();
    await assertSucceeds(
      db.doc('groups/swipesgroup1/swipes/alice_913').update({ decision: 'super', updated_at: now() }),
    );
  });
});

// Personalisierter Boost-Zustand (§7/§18/§17.4): ausschließlich serverseitig
// beschrieben, nur der eigene User darf lesen.
describe('user_preferences/{userId}', () => {
  before(async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().doc('user_preferences/alice').set({
        genre_affinity: { '27': 1.5 },
        disliked_genres: {},
        top_genres: [27],
        last_updated: now(),
      });
    });
  });

  it('erlaubt es dem User, die eigenen Präferenzen zu lesen', async () => {
    const db = testEnv.authenticatedContext('alice').firestore();
    await assertSucceeds(db.doc('user_preferences/alice').get());
  });

  it('lehnt es ab, dass ein anderer Nutzer fremde Präferenzen liest', async () => {
    const db = testEnv.authenticatedContext('bob').firestore();
    await assertFails(db.doc('user_preferences/alice').get());
  });

  it('lehnt unauthentifiziertes Lesen ab', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(db.doc('user_preferences/alice').get());
  });

  it('lehnt es ab, dass der Owner selbst seine Präferenzen schreibt (nur serverseitig)', async () => {
    const db = testEnv.authenticatedContext('alice').firestore();
    await assertFails(
      db.doc('user_preferences/alice').set({
        genre_affinity: { '99': 100 },
        disliked_genres: {},
        top_genres: [99],
        last_updated: now(),
      }),
    );
  });

  it('lehnt es ab, dass ein fremder Nutzer ein Präferenzen-Dokument für einen anderen User anlegt', async () => {
    const db = testEnv.authenticatedContext('bob').firestore();
    await assertFails(
      db.doc('user_preferences/carol').set({
        genre_affinity: {},
        disliked_genres: {},
        top_genres: [],
        last_updated: now(),
      }),
    );
  });

  it('lehnt es ab, dass der Owner selbst seine Präferenzen löscht', async () => {
    const db = testEnv.authenticatedContext('alice').firestore();
    await assertFails(db.doc('user_preferences/alice').delete());
  });
});

// Premium-Status (§15, Voraussetzung für Super Swipe): ausschließlich
// serverseitig beschrieben, nur der eigene User darf lesen - kein Client
// darf sich selbst Premium-Rechte einräumen.
describe('premium_status/{userId}', () => {
  before(async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().doc('premium_status/dave').set({ is_premium: true });
    });
  });

  it('erlaubt es dem User, den eigenen Premium-Status zu lesen', async () => {
    const db = testEnv.authenticatedContext('dave').firestore();
    await assertSucceeds(db.doc('premium_status/dave').get());
  });

  it('lehnt es ab, dass ein anderer Nutzer einen fremden Premium-Status liest', async () => {
    const db = testEnv.authenticatedContext('bob').firestore();
    await assertFails(db.doc('premium_status/dave').get());
  });

  it('lehnt unauthentifiziertes Lesen ab', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(db.doc('premium_status/dave').get());
  });

  it('lehnt es ab, dass sich der Owner selbst Premium-Status einräumt (nur serverseitig)', async () => {
    const db = testEnv.authenticatedContext('bob').firestore();
    await assertFails(db.doc('premium_status/bob').set({ is_premium: true }));
  });

  it('lehnt es ab, dass ein Nutzer den Premium-Status eines anderen Users setzt', async () => {
    const db = testEnv.authenticatedContext('bob').firestore();
    await assertFails(db.doc('premium_status/carol').set({ is_premium: true }));
  });

  it('lehnt es ab, dass der Owner seinen eigenen Premium-Status aktualisiert', async () => {
    const db = testEnv.authenticatedContext('dave').firestore();
    await assertFails(db.doc('premium_status/dave').update({ is_premium: false }));
  });

  it('lehnt es ab, dass der Owner seinen eigenen Premium-Status löscht', async () => {
    const db = testEnv.authenticatedContext('dave').firestore();
    await assertFails(db.doc('premium_status/dave').delete());
  });
});
