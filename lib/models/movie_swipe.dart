import 'package:cloud_firestore/cloud_firestore.dart';

enum SwipeDecision {
  like,
  dislike,
  skip,
  watchlist;

  static SwipeDecision fromString(String value) {
    return SwipeDecision.values.firstWhere(
      (decision) => decision.name == value,
      orElse: () => SwipeDecision.dislike,
    );
  }
}

/// Die Entscheidung eines Users zu einem Film innerhalb einer Gruppe
/// (`groups/{groupId}/swipes/{uid}_{movieId}`). TMDB bleibt die Quelle der
/// eigentlichen Filmdaten - hier wird nur die Entscheidung gespeichert.
///
/// [genreIds] sind die TMDB-Genre-IDs des Films zum Zeitpunkt des Swipes -
/// keine vollständigen Filmdaten (nur numerische IDs), ausschließlich für
/// den Boost-Algorithmus (§7/§18 der Master-Spezifikation: Genre-Präferenz
/// und Anti-Boost werten die eigene Like/Dislike-Historie aus, ohne dafür
/// bei jeder Berechnung erneut TMDB abzufragen). Bei bereits bestehenden
/// (älteren) Dokumenten ohne dieses Feld ist die Liste leer - robust
/// gegenüber Legacy-Daten.
class MovieSwipe {
  const MovieSwipe({
    required this.uid,
    required this.movieId,
    required this.decision,
    required this.createdAt,
    required this.updatedAt,
    this.genreIds = const [],
  });

  final String uid;
  final int movieId;
  final SwipeDecision decision;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<int> genreIds;

  factory MovieSwipe.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    final createdAtValue = data['created_at'];
    final updatedAtValue = data['updated_at'];
    final genreIdsValue = data['genre_ids'] as List?;
    return MovieSwipe(
      uid: data['uid'] as String? ?? '',
      movieId: (data['movie_id'] as num?)?.toInt() ?? 0,
      decision: SwipeDecision.fromString(data['decision'] as String? ?? 'dislike'),
      createdAt: createdAtValue is Timestamp ? createdAtValue.toDate() : DateTime.now(),
      updatedAt: updatedAtValue is Timestamp ? updatedAtValue.toDate() : DateTime.now(),
      genreIds: genreIdsValue?.whereType<num>().map((n) => n.toInt()).toList() ?? const [],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'uid': uid,
      'movie_id': movieId,
      'decision': decision.name,
      'created_at': Timestamp.fromDate(createdAt),
      'updated_at': Timestamp.fromDate(updatedAt),
      'genre_ids': genreIds,
    };
  }
}
