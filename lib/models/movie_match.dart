import 'package:cloud_firestore/cloud_firestore.dart';

/// Ein Gruppen-Match (`groups/{groupId}/matches/{movieId}`) - ein Film, den
/// alle aktuellen Mitglieder der Gruppe geliked haben. Enthält bewusst nur
/// die für die Match-Funktion nötigen Daten, kein TMDB-JSON: die eigentlichen
/// Filmdaten werden beim Anzeigen live über [movieId] von TMDB nachgeladen.
///
/// Kein `toFirestore()`: Match-Dokumente werden ausschließlich serverseitig
/// von der Cloud Function `functions/index.js` erzeugt (Admin-SDK, umgeht die
/// Firestore Security Rules) - der Client liest hier nur, er schreibt nie.
class MovieMatch {
  const MovieMatch({
    required this.movieId,
    required this.memberCount,
    required this.likeCount,
    required this.createdAt,
  });

  final int movieId;
  final int memberCount;
  final int likeCount;
  final DateTime createdAt;

  factory MovieMatch.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    final createdAtValue = data['created_at'];
    return MovieMatch(
      movieId: (data['movie_id'] as num?)?.toInt() ?? 0,
      memberCount: (data['member_count'] as num?)?.toInt() ?? 0,
      likeCount: (data['like_count'] as num?)?.toInt() ?? 0,
      createdAt: createdAtValue is Timestamp ? createdAtValue.toDate() : DateTime.now(),
    );
  }
}
