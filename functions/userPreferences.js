'use strict';

/**
 * Serverseitige Pflege des personalisierten Boost-Zustands eines Users
 * (`user_preferences/{uid}`, §17.4/§18 der Master-Spezifikation: "In Cloud
 * Function Nutzer-Historie analysieren und user_preferences aktualisieren").
 * Läuft ausschließlich mit Admin-Rechten - Firestore Security Rules
 * verbieten jedem Client das Schreiben dieses Dokuments vollständig.
 *
 * Global pro User über alle Gruppen hinweg (das Schema in §17.4 kennt kein
 * `group_id`-Feld) - anders als der gruppenscoped Freundes-Likes-Boost
 * (§18), der weiterhin clientseitig pro Gruppe berechnet wird.
 *
 * Faktoren (§7):
 * - **Genre-Präferenz**: die Summe der zeitverfallsgewichteten Likes pro
 *   Genre ("Persönliche Genre-Präferenz: Auswertung der eigenen
 *   Like-Historie"). Nur Likes tragen bei - Dislikes fließen bewusst nicht
 *   negativ in dieselbe Zahl ein, das leistet bereits der separate
 *   Anti-Boost.
 * - **Anti-Boost**: reine Zählung, wie oft der User ein Genre bereits
 *   disliked hat, ohne Zeitverfall (§7 nennt den Verfall ausdrücklich nur
 *   für "ältere Likes").
 * - **Zeitbasierter Verfall**: linear über 30 Tage auf 0 (konkreter Wert
 *   ist in der Master-Spezifikation nicht vorgegeben - mit dem
 *   Produktverantwortlichen abgestimmt).
 *
 * "Oft geliked" (§7, Grund-Boost) = Top-3-Genres nach Affinität (ebenfalls
 * mit dem Produktverantwortlichen abgestimmt) - wird hier bereits als
 * `top_genres` vorberechnet, damit der Client nicht dieselbe Sortierlogik
 * ein zweites Mal (in Dart) nachbauen muss.
 */

const GENRE_AFFINITY_DECAY_DAYS = 30;
const TOP_GENRE_COUNT = 3;
const MS_PER_DAY = 24 * 60 * 60 * 1000;

/**
 * Linearer Verfall: 1.0 am Tag des Likes, fällt linear auf 0.0 nach
 * [GENRE_AFFINITY_DECAY_DAYS] Tagen, danach konstant 0.
 */
function decayWeight(likedAt, now) {
  const ageDays = (now.getTime() - likedAt.getTime()) / MS_PER_DAY;
  if (ageDays <= 0) return 1;
  if (ageDays >= GENRE_AFFINITY_DECAY_DAYS) return 0;
  return 1 - ageDays / GENRE_AFFINITY_DECAY_DAYS;
}

function toDate(value, fallback) {
  if (value && typeof value.toDate === 'function') return value.toDate();
  return fallback;
}

function mapToObject(map) {
  const obj = {};
  for (const [key, value] of map.entries()) {
    obj[String(key)] = value;
  }
  return obj;
}

/**
 * Wertet die komplette (gruppenübergreifende) Swipe-Historie von [uid] aus
 * und schreibt das Ergebnis nach `user_preferences/{uid}`. Idempotent und
 * ohne Seiteneffekte auf andere User - kann beliebig oft für denselben User
 * neu berechnet werden (voller Rescan statt inkrementeller Zähler, damit
 * gelöschte/geänderte Swipes - z. B. Watchlist-Entfernen - automatisch
 * korrekt berücksichtigt werden, ohne eine separate Dekrement-Logik zu
 * benötigen).
 *
 * @param {{
 *   firestore: FirebaseFirestore.Firestore,
 *   uid: string,
 *   now?: Date,
 * }} params
 */
async function updateUserGenrePreferences({ firestore, uid, now = new Date() }) {
  if (typeof uid !== 'string' || uid.trim().length === 0) {
    throw new Error('updateUserGenrePreferences: ungültige uid');
  }

  const swipesSnap = await firestore.collectionGroup('swipes').where('uid', '==', uid).get();

  const genreAffinity = new Map();
  const dislikedGenres = new Map();

  for (const doc of swipesSnap.docs) {
    const data = doc.data();
    const genreIds = Array.isArray(data.genre_ids) ? data.genre_ids : [];
    if (genreIds.length === 0) continue;

    if (data.decision === 'like') {
      const likedAt = toDate(data.created_at, now);
      const weight = decayWeight(likedAt, now);
      if (weight <= 0) continue;
      for (const genreId of genreIds) {
        if (typeof genreId !== 'number') continue;
        genreAffinity.set(genreId, (genreAffinity.get(genreId) ?? 0) + weight);
      }
    } else if (data.decision === 'dislike') {
      for (const genreId of genreIds) {
        if (typeof genreId !== 'number') continue;
        dislikedGenres.set(genreId, (dislikedGenres.get(genreId) ?? 0) + 1);
      }
    }
  }

  // "Oft geliked" (§7) = Top-3-Genres nach Affinität; bei Gleichstand nach
  // Genre-ID sortiert, damit das Ergebnis deterministisch/testbar bleibt.
  const topGenres = [...genreAffinity.entries()]
    .filter(([, score]) => score > 0)
    .sort((a, b) => b[1] - a[1] || a[0] - b[0])
    .slice(0, TOP_GENRE_COUNT)
    .map(([genreId]) => genreId);

  await firestore
    .collection('user_preferences')
    .doc(uid)
    .set({
      genre_affinity: mapToObject(genreAffinity),
      disliked_genres: mapToObject(dislikedGenres),
      top_genres: topGenres,
      last_updated: now,
    });

  return { topGenres, genreAffinity: mapToObject(genreAffinity), dislikedGenres: mapToObject(dislikedGenres) };
}

module.exports = {
  updateUserGenrePreferences,
  decayWeight,
  GENRE_AFFINITY_DECAY_DAYS,
  TOP_GENRE_COUNT,
};
