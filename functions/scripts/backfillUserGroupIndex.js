'use strict';

/**
 * Einmaliges Backfill für den User-Group-Index `users/{uid}/groups/{groupId}`
 * (PO-Entscheidung, siehe README "Architekturentscheidung" und
 * `functions/userGroupIndex.js`). Der Cloud-Function-Trigger
 * `onGroupMemberWritten` pflegt den Index nur für Mitgliedschaften, die NACH
 * seinem Deployment angelegt/gelöscht werden - bereits vor dem Deployment
 * bestehende Mitgliedschaften haben noch keinen Index-Eintrag. Dieses Skript
 * liest exakt dieselben, bereits bestehenden Daten (`groups/{groupId}` und
 * `groups/{groupId}/members`), die auch der Trigger als Wahrheit ansieht,
 * und legt für jede bestehende Mitgliedschaft den entsprechenden
 * Index-Eintrag an.
 *
 * Kein dauerhaftes Produkt-Feature, kein Deployment-Ziel - wird manuell mit
 * Node ausgeführt (siehe functions/README.md, Abschnitt "Backfill").
 *
 * Idempotent: `set()` auf einen deterministischen Dokumentpfad
 * (`users/{uid}/groups/{groupId}`) mit demselben Inhalt erzeugt bei
 * wiederholter Ausführung keine doppelten oder abweichenden Daten - ein
 * erneuter Lauf überschreibt vorhandene, korrekte Einträge lediglich mit
 * sich selbst.
 *
 * Nutzung:
 *   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 GCLOUD_PROJECT=<project> \
 *     node scripts/backfillUserGroupIndex.js
 *
 * Gegen eine echte Firebase-Produktionsinstanz (ohne FIRESTORE_EMULATOR_HOST)
 * NICHT ohne ausdrückliche, separate Freigabe ausführen - siehe README.
 */

const admin = require('firebase-admin');

async function backfillUserGroupIndex(firestore) {
  const groupsSnapshot = await firestore.collection('groups').get();

  let groupCount = 0;
  let memberCount = 0;

  for (const groupDoc of groupsSnapshot.docs) {
    groupCount += 1;
    const groupId = groupDoc.id;
    const membersSnapshot = await firestore.collection('groups').doc(groupId).collection('members').get();

    for (const memberDoc of membersSnapshot.docs) {
      const uid = memberDoc.id;
      await firestore.doc(`users/${uid}/groups/${groupId}`).set({ groupId });
      memberCount += 1;
    }
  }

  return { groupCount, memberCount };
}

async function main() {
  if (admin.apps.length === 0) {
    admin.initializeApp();
  }
  const firestore = admin.firestore();

  const isEmulator = Boolean(process.env.FIRESTORE_EMULATOR_HOST);
  if (!isEmulator) {
    // eslint-disable-next-line no-console
    console.log(
      'FIRESTORE_EMULATOR_HOST ist nicht gesetzt - dieses Skript würde gegen eine echte ' +
        'Firebase-Instanz laufen. Abgebrochen. Siehe functions/README.md, Abschnitt "Backfill".',
    );
    process.exitCode = 1;
    return;
  }

  const { groupCount, memberCount } = await backfillUserGroupIndex(firestore);
  // eslint-disable-next-line no-console
  console.log(`Backfill abgeschlossen: ${groupCount} Gruppen, ${memberCount} Index-Einträge geschrieben/aktualisiert.`);
}

if (require.main === module) {
  main().catch((error) => {
    // eslint-disable-next-line no-console
    console.error('Backfill fehlgeschlagen:', error);
    process.exitCode = 1;
  });
}

module.exports = { backfillUserGroupIndex };
