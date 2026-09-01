import 'package:cloud_firestore/cloud_firestore.dart';

enum SwipeDecision {
  like,
  dislike,
  skip,
  watchlist,

  /// "Super Swipe" (§6/§15 der Master-Spezifikation, Premium-Feature):
  /// "Signalisiert der Gruppe: 'Den will ich unbedingt sehen!'". Zählt für
  /// die Match-Erkennung wie ein Like (`functions/matchEngine.js`), aber
  /// ohne eigenen Boost-Bonus in der Score-Formel - dieser Wert ist in der
  /// Master-Spezifikation nicht beziffert und deshalb noch nicht
  /// implementiert (mit dem Produktverantwortlichen abgestimmt).
  superSwipe;

  /// Der in Firestore gespeicherte String (§17.4-Schema: `swipe_type` enum
  /// `'like'|'dislike'|'skip'|'watchlist'|'super'`). Für alle Werte außer
  /// [superSwipe] identisch mit [name]; `super` ist ein reserviertes
  /// Dart-Schlüsselwort und kann nicht als Enum-Bezeichner verwendet werden,
  /// daher diese explizite Zuordnung statt eines blinden `.name`.
  String get firestoreValue => this == SwipeDecision.superSwipe ? 'super' : name;

  static SwipeDecision fromString(String value) {
    if (value == 'super') return SwipeDecision.superSwipe;
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
/// bei jeder Berechnung erneut TMDB abzufragen). [castIds] sind analog die
/// Top-3-Hauptdarsteller-IDs (siehe `selectMainCastIds`), Grundlage für den
/// Cast-Anti-Boost ("gleicher Hauptdarsteller"). Bei bereits bestehenden
/// (älteren) Dokumenten ohne diese Felder sind die Listen leer - robust
/// gegenüber Legacy-Daten.
class MovieSwipe {
  const MovieSwipe({
    required this.uid,
    required this.movieId,
    required this.decision,
    required this.createdAt,
    required this.updatedAt,
    this.genreIds = const [],
    this.castIds = const [],
  });

  final String uid;
  final int movieId;
  final SwipeDecision decision;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<int> genreIds;
  final List<int> castIds;

  factory MovieSwipe.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    final createdAtValue = data['created_at'];
    final updatedAtValue = data['updated_at'];
    final genreIdsValue = data['genre_ids'] as List?;
    final castIdsValue = data['cast_ids'] as List?;
    return MovieSwipe(
      uid: data['uid'] as String? ?? '',
      movieId: (data['movie_id'] as num?)?.toInt() ?? 0,
      decision: SwipeDecision.fromString(data['decision'] as String? ?? 'dislike'),
      createdAt: createdAtValue is Timestamp ? createdAtValue.toDate() : DateTime.now(),
      updatedAt: updatedAtValue is Timestamp ? updatedAtValue.toDate() : DateTime.now(),
      genreIds: genreIdsValue?.whereType<num>().map((n) => n.toInt()).toList() ?? const [],
      castIds: castIdsValue?.whereType<num>().map((n) => n.toInt()).toList() ?? const [],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'uid': uid,
      'movie_id': movieId,
      'decision': decision.firestoreValue,
      'created_at': Timestamp.fromDate(createdAt),
      'updated_at': Timestamp.fromDate(updatedAt),
      'genre_ids': genreIds,
      'cast_ids': castIds,
    };
  }
}
