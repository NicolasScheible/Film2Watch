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
// lokalen Firestore-Emulator für Filmabend-Abstimmungen (§21:
// "Filmabend-Abstimmung" - mehrere Terminvorschläge, Mehrfachauswahl pro
// Teilnehmer, feste Deadline, automatische Auswertung durch die Scheduled
// Cloud Function `functions/moviePollEngine.js`).
const serverTimestamp = () => firebase.firestore.FieldValue.serverTimestamp();

let testEnv;
const now = () => new Date();
const inFuture = (ms = 24 * 60 * 60 * 1000) => new Date(Date.now() + ms);
const inPast = (ms = 60 * 1000) => new Date(Date.now() - ms);

function validPoll(overrides = {}) {
  return {
    created_by: 'alice',
    created_at: serverTimestamp(),
    deadline: inFuture(),
    status: 'open',
    ...overrides,
  };
}

function validOption(overrides = {}) {
  return {
    scheduled_at: now(),
    platform_id: 8,
    ...overrides,
  };
}

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
    await db.doc('groups/pollgroup1').set({
      id: 'pollgroup1',
      name: 'Filmabend',
      photo_url: null,
      created_by: 'alice',
      created_at: now(),
      updated_at: now(),
    });
    await db.doc('groups/pollgroup1/members/alice').set({ uid: 'alice', role: 'admin', joined_at: now() });
    await db.doc('groups/pollgroup1/members/bob').set({ uid: 'bob', role: 'member', joined_at: now() });
    await db.doc('groups/pollgroup1/members/carol_member').set({
      uid: 'carol_member',
      role: 'member',
      joined_at: now(),
    });
    // dave ist kein Mitglied von pollgroup1.

    await db.doc('groups/pollgroup1/matches/550').set({
      movie_id: 550,
      member_uids: ['alice', 'bob'],
      matched_at: now(),
    });

    // Eine bestehende, offene Abstimmung von bob mit zwei Optionen -
    // Grundlage für die Options-/Votes-Tests.
    await db.doc('groups/pollgroup1/movie_night_polls/bobs-poll').set(validPoll({ created_by: 'bob' }));
    await db
      .doc('groups/pollgroup1/movie_night_polls/bobs-poll/options/opt1')
      .set(validOption({ platform_id: 8 }));
    await db
      .doc('groups/pollgroup1/movie_night_polls/bobs-poll/options/opt2')
      .set(validOption({ platform_id: 9 }));

    // Eine bereits abgelaufene Abstimmung (Deadline in der Vergangenheit,
    // status noch "open" - simuliert den Zustand kurz vor Auswertung durch
    // die Scheduled Cloud Function) - Grundlage für die Deadline-Tests.
    await db.doc('groups/pollgroup1/movie_night_polls/expired-poll').set(
      validPoll({ created_by: 'bob', deadline: inPast() }),
    );
    await db
      .doc('groups/pollgroup1/movie_night_polls/expired-poll/options/opt1')
      .set(validOption({ platform_id: 8 }));

    // Eine bereits ausgewertete (geschlossene) Abstimmung - simuliert das
    // Ergebnis der Scheduled Cloud Function, ohne sie hier auszuführen.
    await db.doc('groups/pollgroup1/movie_night_polls/closed-poll').set(
      validPoll({
        created_by: 'bob',
        deadline: inPast(),
        status: 'closed',
        winning_option_id: 'opt1',
        result_movie_night_id: 'mn1',
        resolved_at: now(),
      }),
    );
    await db
      .doc('groups/pollgroup1/movie_night_polls/closed-poll/options/opt1')
      .set(validOption({ platform_id: 8 }));
  });
});

after(async () => {
  await testEnv.cleanup();
});

describe('groups/{groupId}/movie_night_polls/{pollId}', () => {
  it('lehnt unauthentifiziertes Lesen ab', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(db.collection('groups/pollgroup1/movie_night_polls').get());
  });

  it('lehnt das Lesen durch ein Nicht-Mitglied ab', async () => {
    const db = testEnv.authenticatedContext('dave').firestore();
    await assertFails(db.doc('groups/pollgroup1/movie_night_polls/bobs-poll').get());
  });

  it('erlaubt einem Mitglied das Lesen', async () => {
    const db = testEnv.authenticatedContext('carol_member').firestore();
    await assertSucceeds(db.doc('groups/pollgroup1/movie_night_polls/bobs-poll').get());
  });

  it('erlaubt jedem Mitglied das Anlegen einer Abstimmung', async () => {
    const db = testEnv.authenticatedContext('carol_member').firestore();
    await assertSucceeds(
      db.collection('groups/pollgroup1/movie_night_polls').add(validPoll({ created_by: 'carol_member' })),
    );
  });

  it('lehnt unauthentifiziertes Anlegen ab', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(db.collection('groups/pollgroup1/movie_night_polls').add(validPoll()));
  });

  it('lehnt das Anlegen durch ein Nicht-Mitglied ab', async () => {
    const db = testEnv.authenticatedContext('dave').firestore();
    await assertFails(
      db.collection('groups/pollgroup1/movie_night_polls').add(validPoll({ created_by: 'dave' })),
    );
  });

  it('lehnt es ab, dass ein Mitglied eine Abstimmung im Namen eines anderen Users anlegt (UID-Manipulation)', async () => {
    const db = testEnv.authenticatedContext('carol_member').firestore();
    await assertFails(
      db.collection('groups/pollgroup1/movie_night_polls').add(validPoll({ created_by: 'alice' })),
    );
  });

  it('lehnt eine erfundene created_at-Zeit ab (keine Client-Zeit)', async () => {
    const db = testEnv.authenticatedContext('carol_member').firestore();
    await assertFails(
      db.collection('groups/pollgroup1/movie_night_polls').add({
        created_by: 'carol_member',
        created_at: new Date('2020-01-01'),
        deadline: inFuture(),
        status: 'open',
      }),
    );
  });

  it('lehnt eine deadline in der Vergangenheit ab', async () => {
    const db = testEnv.authenticatedContext('carol_member').firestore();
    await assertFails(
      db.collection('groups/pollgroup1/movie_night_polls').add(
        validPoll({ created_by: 'carol_member', deadline: inPast() }),
      ),
    );
  });

  it('lehnt eine deadline ab, die kein Timestamp ist', async () => {
    const db = testEnv.authenticatedContext('carol_member').firestore();
    await assertFails(
      db.collection('groups/pollgroup1/movie_night_polls').add({
        created_by: 'carol_member',
        created_at: serverTimestamp(),
        deadline: 'morgen',
        status: 'open',
      }),
    );
  });

  it('lehnt einen anderen status als "open" beim Anlegen ab', async () => {
    const db = testEnv.authenticatedContext('carol_member').firestore();
    await assertFails(
      db.collection('groups/pollgroup1/movie_night_polls').add(
        validPoll({ created_by: 'carol_member', status: 'closed' }),
      ),
    );
  });

  it('lehnt es ab, dass der Client selbst einen Gewinner setzt (winning_option_id)', async () => {
    const db = testEnv.authenticatedContext('carol_member').firestore();
    await assertFails(
      db.collection('groups/pollgroup1/movie_night_polls').add({
        ...validPoll({ created_by: 'carol_member' }),
        winning_option_id: 'opt1',
      }),
    );
  });

  it('lehnt unzulässige Zusatzfelder ab', async () => {
    const db = testEnv.authenticatedContext('carol_member').firestore();
    await assertFails(
      db.collection('groups/pollgroup1/movie_night_polls').add({
        ...validPoll({ created_by: 'carol_member' }),
        note: 'geheimer Favorit',
      }),
    );
  });

  it('lehnt jedes Bearbeiten der Abstimmung ab, auch durch den Ersteller', async () => {
    const db = testEnv.authenticatedContext('bob').firestore();
    await assertFails(
      db.doc('groups/pollgroup1/movie_night_polls/bobs-poll').update({ status: 'closed' }),
    );
  });

  it('lehnt jedes Löschen der Abstimmung ab, auch durch den Ersteller oder einen Admin', async () => {
    const dbBob = testEnv.authenticatedContext('bob').firestore();
    await assertFails(dbBob.doc('groups/pollgroup1/movie_night_polls/bobs-poll').delete());
    const dbAlice = testEnv.authenticatedContext('alice').firestore();
    await assertFails(dbAlice.doc('groups/pollgroup1/movie_night_polls/bobs-poll').delete());
  });

  describe('options', () => {
    it('erlaubt dem Ersteller, eine Option zur eigenen, noch offenen Abstimmung hinzuzufügen', async () => {
      const db = testEnv.authenticatedContext('bob').firestore();
      await assertSucceeds(
        db.collection('groups/pollgroup1/movie_night_polls/bobs-poll/options').add(validOption()),
      );
    });

    it('lehnt es ab, dass ein anderes Mitglied eine Option zu einer fremden Abstimmung hinzufügt', async () => {
      const db = testEnv.authenticatedContext('carol_member').firestore();
      await assertFails(
        db.collection('groups/pollgroup1/movie_night_polls/bobs-poll/options').add(validOption()),
      );
    });

    it('lehnt es ab, eine Option zu einer bereits abgelaufenen Abstimmung hinzuzufügen', async () => {
      const db = testEnv.authenticatedContext('bob').firestore();
      await assertFails(
        db.collection('groups/pollgroup1/movie_night_polls/expired-poll/options').add(validOption()),
      );
    });

    it('lehnt es ab, eine Option zu einer bereits geschlossenen Abstimmung hinzuzufügen', async () => {
      const db = testEnv.authenticatedContext('bob').firestore();
      await assertFails(
        db.collection('groups/pollgroup1/movie_night_polls/closed-poll/options').add(validOption()),
      );
    });

    it('erlaubt movie_id, wenn sie ein bestehendes Match der Gruppe ist', async () => {
      const db = testEnv.authenticatedContext('bob').firestore();
      await assertSucceeds(
        db
          .collection('groups/pollgroup1/movie_night_polls/bobs-poll/options')
          .add(validOption({ movie_id: 550 })),
      );
    });

    it('lehnt movie_id ab, die kein Match der Gruppe ist', async () => {
      const db = testEnv.authenticatedContext('bob').firestore();
      await assertFails(
        db
          .collection('groups/pollgroup1/movie_night_polls/bobs-poll/options')
          .add(validOption({ movie_id: 999 })),
      );
    });

    it('lehnt jedes Bearbeiten/Löschen einer Option ab', async () => {
      const db = testEnv.authenticatedContext('bob').firestore();
      await assertFails(
        db.doc('groups/pollgroup1/movie_night_polls/bobs-poll/options/opt1').update({ platform_id: 9 }),
      );
      await assertFails(db.doc('groups/pollgroup1/movie_night_polls/bobs-poll/options/opt1').delete());
    });
  });

  describe('votes', () => {
    it('erlaubt einem Mitglied, für eine Option der offenen Abstimmung zu stimmen', async () => {
      const db = testEnv.authenticatedContext('carol_member').firestore();
      await assertSucceeds(
        db.doc('groups/pollgroup1/movie_night_polls/bobs-poll/votes/carol_member_opt1').set({
          uid: 'carol_member',
          option_id: 'opt1',
          voted_at: serverTimestamp(),
        }),
      );
    });

    it('erlaubt demselben Mitglied mehrere Stimmen für verschiedene Optionen (Doodle-Prinzip)', async () => {
      const db = testEnv.authenticatedContext('carol_member').firestore();
      await assertSucceeds(
        db.doc('groups/pollgroup1/movie_night_polls/bobs-poll/votes/carol_member_opt2').set({
          uid: 'carol_member',
          option_id: 'opt2',
          voted_at: serverTimestamp(),
        }),
      );
    });

    it('lehnt unauthentifiziertes Abstimmen ab', async () => {
      const db = testEnv.unauthenticatedContext().firestore();
      await assertFails(
        db.doc('groups/pollgroup1/movie_night_polls/bobs-poll/votes/x_opt1').set({
          uid: 'x',
          option_id: 'opt1',
          voted_at: serverTimestamp(),
        }),
      );
    });

    it('lehnt das Abstimmen durch ein Nicht-Mitglied ab', async () => {
      const db = testEnv.authenticatedContext('dave').firestore();
      await assertFails(
        db.doc('groups/pollgroup1/movie_night_polls/bobs-poll/votes/dave_opt1').set({
          uid: 'dave',
          option_id: 'opt1',
          voted_at: serverTimestamp(),
        }),
      );
    });

    it('lehnt es ab, im Namen eines anderen Users abzustimmen (UID-Manipulation)', async () => {
      const db = testEnv.authenticatedContext('carol_member').firestore();
      await assertFails(
        db.doc('groups/pollgroup1/movie_night_polls/bobs-poll/votes/alice_opt1').set({
          uid: 'alice',
          option_id: 'opt1',
          voted_at: serverTimestamp(),
        }),
      );
    });

    it('lehnt eine Stimme für eine nicht existierende Option ab', async () => {
      const db = testEnv.authenticatedContext('carol_member').firestore();
      await assertFails(
        db.doc('groups/pollgroup1/movie_night_polls/bobs-poll/votes/carol_member_does-not-exist').set({
          uid: 'carol_member',
          option_id: 'does-not-exist',
          voted_at: serverTimestamp(),
        }),
      );
    });

    it('lehnt eine erfundene voted_at-Zeit ab (keine Client-Zeit)', async () => {
      const db = testEnv.authenticatedContext('carol_member').firestore();
      await assertFails(
        db.doc('groups/pollgroup1/movie_night_polls/bobs-poll/votes/carol_member_opt1_v2').set({
          uid: 'carol_member',
          option_id: 'opt1',
          voted_at: new Date('2020-01-01'),
        }),
      );
    });

    it('lehnt eine Dokument-ID ab, die nicht zu uid_optionId passt', async () => {
      const db = testEnv.authenticatedContext('carol_member').firestore();
      await assertFails(
        db.doc('groups/pollgroup1/movie_night_polls/bobs-poll/votes/mismatched-id').set({
          uid: 'carol_member',
          option_id: 'opt1',
          voted_at: serverTimestamp(),
        }),
      );
    });

    it('lehnt eine Stimme nach Ablauf der Deadline ab', async () => {
      const db = testEnv.authenticatedContext('carol_member').firestore();
      await assertFails(
        db.doc('groups/pollgroup1/movie_night_polls/expired-poll/votes/carol_member_opt1').set({
          uid: 'carol_member',
          option_id: 'opt1',
          voted_at: serverTimestamp(),
        }),
      );
    });

    it('lehnt eine Stimme für eine bereits geschlossene Abstimmung ab', async () => {
      const db = testEnv.authenticatedContext('carol_member').firestore();
      await assertFails(
        db.doc('groups/pollgroup1/movie_night_polls/closed-poll/votes/carol_member_opt1').set({
          uid: 'carol_member',
          option_id: 'opt1',
          voted_at: serverTimestamp(),
        }),
      );
    });

    it('erlaubt es einem Mitglied, die eigene Stimme vor der Deadline zu ändern (löschen)', async () => {
      // Eigene (uid, optionId)-Kombination, die in dieser Datei sonst
      // nirgends verwendet wird - ein erneutes `.set()` auf eine anderswo
      // bereits angelegte ID würde von Firestore als `update` statt
      // `create` gewertet und fälschlich an `allow update: if false`
      // scheitern. Löscht die eigene Stimme am Ende wieder, damit spätere
      // Tests (die `bob_opt1` per Rules-Bypass frisch anlegen) unbeeinflusst
      // bleiben.
      const db = testEnv.authenticatedContext('bob').firestore();
      await db.doc('groups/pollgroup1/movie_night_polls/bobs-poll/votes/bob_opt1').set({
        uid: 'bob',
        option_id: 'opt1',
        voted_at: serverTimestamp(),
      });
      await assertSucceeds(
        db.doc('groups/pollgroup1/movie_night_polls/bobs-poll/votes/bob_opt1').delete(),
      );
    });

    it('lehnt es ab, die Stimme eines anderen Users zu löschen', async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().doc('groups/pollgroup1/movie_night_polls/bobs-poll/votes/bob_opt1').set({
          uid: 'bob',
          option_id: 'opt1',
          voted_at: now(),
        });
      });
      const db = testEnv.authenticatedContext('carol_member').firestore();
      await assertFails(
        db.doc('groups/pollgroup1/movie_night_polls/bobs-poll/votes/bob_opt1').delete(),
      );
    });

    it('lehnt jedes Bearbeiten (update) einer Stimme ab', async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().doc('groups/pollgroup1/movie_night_polls/bobs-poll/votes/bob_opt2').set({
          uid: 'bob',
          option_id: 'opt2',
          voted_at: now(),
        });
      });
      const db = testEnv.authenticatedContext('bob').firestore();
      await assertFails(
        db.doc('groups/pollgroup1/movie_night_polls/bobs-poll/votes/bob_opt2').update({ option_id: 'opt1' }),
      );
    });
  });
});
