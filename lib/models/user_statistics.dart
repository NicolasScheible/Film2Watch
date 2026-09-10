import 'movie_swipe.dart';
import 'user_genre_preferences.dart';

/// Persönliche Statistik-Ansicht eines Users (§15: "Detaillierte
/// Statistiken", Premium-Feature) - **mit dem Produktverantwortlichen
/// abgestimmt**: einfache Kennzahlen ausschließlich aus bereits vorhandenen
/// Daten, keine neue Tracking-Infrastruktur. [swipeCount]/[likeCount]/
/// [dislikeCount]/[watchlistCount] werden aus der kompletten,
/// gruppenübergreifenden Swipe-Historie (`SwipeRepository.
/// getAllSwipesForUser`) im Client aggregiert - exakt derselbe Ansatz wie
/// `functions/userPreferences.js` für die Genre-Präferenz. [genrePreferences]
/// wird unverändert übernommen (bereits
/// serverseitig vorberechnet, siehe `UserGenrePreferences`), [matchCount]
/// aus der bereits bestehenden, gruppenübergreifenden Match-Liste
/// (`allMyMatchesProvider`).
class UserStatistics {
  const UserStatistics({
    required this.swipeCount,
    required this.likeCount,
    required this.dislikeCount,
    required this.watchlistCount,
    required this.matchCount,
    required this.genrePreferences,
  });

  static const empty = UserStatistics(
    swipeCount: 0,
    likeCount: 0,
    dislikeCount: 0,
    watchlistCount: 0,
    matchCount: 0,
    genrePreferences: UserGenrePreferences.empty,
  );

  /// Gesamtzahl aller Swipe-Entscheidungen, unabhängig vom Typ (Like/
  /// Dislike/Skip/Watchlist/Super Swipe) - "wie oft habe ich überhaupt
  /// bewertet".
  final int swipeCount;
  final int likeCount;
  final int dislikeCount;
  final int watchlistCount;
  final int matchCount;
  final UserGenrePreferences genrePreferences;

  /// Aggregiert [swipes] (bereits geladen, z. B. per Collection-Group-Query
  /// über alle Gruppen des Users) zu den einzelnen Kennzahlen. Zählt jede
  /// Entscheidung nach ihrem AKTUELLEN Stand (ein Film, der erst geliked und
  /// später auf die Watchlist verschoben wurde, zählt nur als Watchlist) -
  /// dasselbe Dokument kann laut Datenmodell ohnehin nie zwei Entscheidungen
  /// gleichzeitig haben.
  factory UserStatistics.fromSwipes({
    required List<MovieSwipe> swipes,
    required int matchCount,
    required UserGenrePreferences genrePreferences,
  }) {
    var likes = 0;
    var dislikes = 0;
    var watchlist = 0;
    for (final swipe in swipes) {
      switch (swipe.decision) {
        case SwipeDecision.like:
          likes++;
        case SwipeDecision.dislike:
          dislikes++;
        case SwipeDecision.watchlist:
          watchlist++;
        case SwipeDecision.skip:
        case SwipeDecision.superSwipe:
          break;
      }
    }
    return UserStatistics(
      swipeCount: swipes.length,
      likeCount: likes,
      dislikeCount: dislikes,
      watchlistCount: watchlist,
      matchCount: matchCount,
      genrePreferences: genrePreferences,
    );
  }
}
