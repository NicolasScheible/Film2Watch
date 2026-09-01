import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/movie_night.dart';

/// Kapselt den Firestore-Zugriff auf `groups/{groupId}/movie_nights` (§12:
/// "Filmabend planen"). Firestore Auto-ID pro Filmabend, analog zu
/// `ChatRepository`/`messages`.
class MovieNightRepository {
  MovieNightRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _movieNights(String groupId) =>
      _firestore.collection('groups').doc(groupId).collection('movie_nights');

  /// Alle geplanten Filmabende einer Gruppe, chronologisch nach Termin
  /// aufsteigend (der nächste zuerst) - live.
  Stream<List<MovieNight>> watchMovieNights(String groupId) {
    return _movieNights(groupId)
        .orderBy('scheduled_at')
        .snapshots()
        .map((snapshot) => snapshot.docs.map(MovieNight.fromFirestore).toList());
  }

  Future<MovieNight?> getMovieNight({required String groupId, required String movieNightId}) async {
    final snapshot = await _movieNights(groupId).doc(movieNightId).get();
    return snapshot.exists ? MovieNight.fromFirestore(snapshot) : null;
  }

  Future<DocumentReference<Map<String, dynamic>>> createMovieNight({
    required String groupId,
    required String createdBy,
    required DateTime scheduledAt,
    required int platformId,
    int? movieId,
  }) {
    return _movieNights(groupId).add(
      MovieNight.toFirestoreCreate(
        createdBy: createdBy,
        scheduledAt: scheduledAt,
        platformId: platformId,
        movieId: movieId,
      ),
    );
  }

  Future<void> updateMovieNight({
    required String groupId,
    required String movieNightId,
    required DateTime scheduledAt,
    required int platformId,
    int? movieId,
  }) {
    return _movieNights(groupId).doc(movieNightId).update(
          MovieNight.toFirestoreUpdate(
            scheduledAt: scheduledAt,
            platformId: platformId,
            movieId: movieId,
          ),
        );
  }

  /// Absagen/Löschen (§12 nennt diese beiden Begriffe austauschbar für
  /// dieselbe Aktion, kein separater "abgesagt"-Status) - der Filmabend
  /// verschwindet vollständig, analog zu `SwipeRepository.removeSwipe`
  /// ("Watchlist entfernen").
  Future<void> cancelMovieNight({required String groupId, required String movieNightId}) {
    return _movieNights(groupId).doc(movieNightId).delete();
  }
}
