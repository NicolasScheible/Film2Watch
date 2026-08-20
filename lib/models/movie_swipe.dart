import 'package:cloud_firestore/cloud_firestore.dart';

enum SwipeDecision {
  like,
  dislike,
  skip;

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
class MovieSwipe {
  const MovieSwipe({
    required this.uid,
    required this.movieId,
    required this.decision,
    required this.createdAt,
    required this.updatedAt,
  });

  final String uid;
  final int movieId;
  final SwipeDecision decision;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory MovieSwipe.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    final createdAtValue = data['created_at'];
    final updatedAtValue = data['updated_at'];
    return MovieSwipe(
      uid: data['uid'] as String? ?? '',
      movieId: (data['movie_id'] as num?)?.toInt() ?? 0,
      decision: SwipeDecision.fromString(data['decision'] as String? ?? 'dislike'),
      createdAt: createdAtValue is Timestamp ? createdAtValue.toDate() : DateTime.now(),
      updatedAt: updatedAtValue is Timestamp ? updatedAtValue.toDate() : DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'uid': uid,
      'movie_id': movieId,
      'decision': decision.name,
      'created_at': Timestamp.fromDate(createdAt),
      'updated_at': Timestamp.fromDate(updatedAt),
    };
  }
}
