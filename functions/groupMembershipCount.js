'use strict';

// Bewusst der modulare `firebase-admin/firestore`-Import statt
// `admin.firestore.FieldValue` (wie z. B. in `moviePollEngine.js`): dieser
// Trigger reagiert auf `groups/{groupId}/members/{memberUid}`, das Dokument,
// das in nahezu jedem Test-Setup als Allererstes geschrieben wird - dadurch
// ist `onGroupMemberWritten` typischerweise die erste jemals im Prozess
// ausgeführte Cloud Function. `admin.firestore.FieldValue` wird von
// firebase-admin erst durch eine vorherige echte Nutzung der
// Compat-Firestore-Instanz vollständig befüllt; als allererste Function im
// Prozess kam das zu spät (`Cannot read properties of undefined (reading
// 'increment')`, reproduzierbar). Der modulare Import ist synchron beim
// `require()` vollständig verfügbar und unabhängig von dieser Ladereihenfolge.
const { FieldValue } = require('firebase-admin/firestore');

/**
 * Hält `group_membership_counts/{uid}.count` aktuell (§15: Free-Gruppen-
 * Limit von 3, unbegrenzt für Premium - mit dem Produktverantwortlichen
 * abgestimmt). Wird von `onGroupMemberWritten` (siehe `functions/index.js`)
 * bei jedem Anlegen/Löschen einer `groups/{groupId}/members/{memberUid}`-
 * Mitgliedschaft aufgerufen, niemals bei einer reinen Rollenänderung
 * (Anlegen/Löschen ändert die tatsächliche Anzahl der Gruppen, ein Update
 * der Rolle nicht).
 *
 * `FieldValue.increment()` mit `set(..., {merge: true})` ist bei einem noch
 * nicht existierenden Dokument sicher (initialisiert bei 0) und - wichtiger -
 * bei gleichzeitigen Aufrufen (mehrere Mitgliedschaften desselben Users
 * werden parallel anlegt/gelöscht) atomar auf Firestore-Ebene: kein manuelles
 * Read-Modify-Write, das sich bei einer Race Condition gegenseitig
 * überschreiben könnte.
 *
 * Die serverseitige Firestore-Rule `groupMembershipCount()` liest diesen
 * Zähler synchron beim Anlegen einer neuen Mitgliedschaft - da dieser
 * Trigger asynchron NACH dem eigentlichen Schreibvorgang läuft, gibt es ein
 * eng begrenztes Zeitfenster, in dem mehrere nahezu gleichzeitige
 * Beitritte (bevor der Trigger für die vorherigen durchgelaufen ist) den
 * Zähler kurzzeitig hinter der Realität zurückbleiben lassen können. Für den
 * regulären, sequenziellen Anwendungsfall (ein User legt eine Gruppe an,
 * wartet auf Erfolg, legt die nächste an) ist das Limit exakt bei der
 * 4. Gruppe wirksam, da die reale Nutzerinteraktion immer deutlich langsamer
 * ist als die Trigger-Verarbeitung.
 *
 * @param {{ firestore: FirebaseFirestore.Firestore, uid: string, delta: 1 | -1 }} params
 */
async function applyMembershipCountDelta({ firestore, uid, delta }) {
  await firestore.doc(`group_membership_counts/${uid}`).set(
    { count: FieldValue.increment(delta) },
    { merge: true },
  );
}

module.exports = { applyMembershipCountDelta };
