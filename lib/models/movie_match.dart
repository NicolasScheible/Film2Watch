import 'package:cloud_firestore/cloud_firestore.dart';

/// Ein Gruppen-Match (`groups/{groupId}/matches/{movieId}`) - ein Film, den
/// alle aktuellen Mitglieder der Gruppe geliked haben. Enthält bewusst nur
/// die für die Match-Funktion nötigen Daten, kein TMDB-JSON: die eigentlichen
/// Filmdaten werden beim Anzeigen live über [movieId] von TMDB nachgeladen.
///
/// Kein `toFirestore()`: Match-Dokumente werden ausschließlich serverseitig
/// von den Cloud Functions (`functions/matchEngine.js`, Admin-SDK) erzeugt -
/// die Firestore Security Rules verbieten jeden Client-Schreibzugriff
/// kategorisch (`allow write: if false`). Der Client liest hier nur.
class MovieMatch {
  const MovieMatch({
    required this.movieId,
    required this.memberUids,
    required this.matchedAt,
  });

  final int movieId;

  /// Die Mitglieder, die diesen Film geliked und damit den Match ausgelöst
  /// haben - eine Momentaufnahme zum Zeitpunkt des Matches, unabhängig von
  /// späteren Mitgliedschaftsänderungen.
  final List<String> memberUids;

  final DateTime matchedAt;

  factory MovieMatch.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    final matchedAtValue = data['matched_at'];
    return MovieMatch(
      movieId: (data['movie_id'] as num?)?.toInt() ?? 0,
      memberUids: (data['member_uids'] as List<dynamic>?)?.cast<String>() ?? const [],
      matchedAt: matchedAtValue is Timestamp ? matchedAtValue.toDate() : DateTime.now(),
    );
  }
}
