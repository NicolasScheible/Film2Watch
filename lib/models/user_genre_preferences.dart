import 'package:cloud_firestore/cloud_firestore.dart';

/// Der personalisierte Boost-Zustand eines Users (`user_preferences/{uid}`,
/// §17.4 der Master-Spezifikation), serverseitig gepflegt von der Cloud
/// Function `functions/userPreferences.js` (§18: "In Cloud Function
/// Nutzer-Historie analysieren und user_preferences aktualisieren") -
/// clientseitig ausschließlich lesend verwendet, siehe Firestore Rules
/// (`allow write: if false`).
///
/// Global pro User, nicht pro Gruppe (das Schema in §17.4 kennt kein
/// `group_id`-Feld) - die eigene Genre-Vorliebe/Abneigung ist gruppen-
/// übergreifend dieselbe Person.
class UserGenrePreferences {
  const UserGenrePreferences({
    required this.genreAffinity,
    required this.dislikedGenres,
    required this.topGenres,
    required this.dislikedCastIds,
  });

  /// Leerer Ausgangszustand für User ohne (oder mit noch nicht ausgewerteter)
  /// Swipe-Historie - kein Boost/Anti-Boost-Signal.
  static const empty = UserGenrePreferences(
    genreAffinity: {},
    dislikedGenres: {},
    topGenres: {},
    dislikedCastIds: {},
  );

  /// Zeitlich verfallsgewichtete Summe der Likes pro Genre-ID (§7:
  /// "genre_affinity: map (genre_id -> score)"). Nur zu Diagnose-/
  /// Nachvollziehbarkeitszwecken clientseitig verfügbar - für den
  /// Boost-Score selbst wird [topGenres] verwendet.
  final Map<int, double> genreAffinity;

  /// Anzahl Dislikes pro Genre-ID (ohne Zeitverfall) - Grundlage für den
  /// Genre-Anti-Boost (§7: "Ein Dislike senkt den Score ähnlicher Filme").
  final Map<int, int> dislikedGenres;

  /// Die (bis zu drei) Genres mit der höchsten [genreAffinity] - "oft
  /// geliked" im Sinne von §7's Grund-Boost (+30).
  final Set<int> topGenres;

  /// Anzahl Dislikes pro TMDB-Personen-ID unter den Top-3-Hauptdarstellern
  /// des jeweils gedislikten Films (ohne Zeitverfall, analog zu
  /// [dislikedGenres]) - Grundlage für den Cast-Anti-Boost (§7: "gleicher
  /// Hauptdarsteller").
  final Map<int, int> dislikedCastIds;

  factory UserGenrePreferences.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) return empty;

    final affinityRaw = data['genre_affinity'] as Map<String, dynamic>? ?? const {};
    final dislikedRaw = data['disliked_genres'] as Map<String, dynamic>? ?? const {};
    final topGenresRaw = data['top_genres'] as List? ?? const [];
    final dislikedCastRaw = data['disliked_cast_ids'] as Map<String, dynamic>? ?? const {};

    return UserGenrePreferences(
      genreAffinity: _parseIntKeyedMap(affinityRaw).map((k, v) => MapEntry(k, v.toDouble())),
      dislikedGenres: _parseIntKeyedMap(dislikedRaw).map((k, v) => MapEntry(k, v.toInt())),
      topGenres: topGenresRaw.whereType<num>().map((n) => n.toInt()).toSet(),
      dislikedCastIds: _parseIntKeyedMap(dislikedCastRaw).map((k, v) => MapEntry(k, v.toInt())),
    );
  }

  /// Firestore-Map-Keys sind immer Strings ("genre_id -> score", §17.4) -
  /// wandelt sie robust in numerische Genre-IDs um; nicht-numerische Keys
  /// (sollten nie vorkommen) werden übersprungen statt einen Fehler zu
  /// werfen.
  static Map<int, num> _parseIntKeyedMap(Map<String, dynamic> raw) {
    final result = <int, num>{};
    for (final entry in raw.entries) {
      final genreId = int.tryParse(entry.key);
      if (genreId == null) continue;
      result[genreId] = (entry.value as num?) ?? 0;
    }
    return result;
  }
}
