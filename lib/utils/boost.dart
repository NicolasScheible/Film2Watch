import 'dart:math';

import '../models/movie.dart';
import '../models/movie_swipe.dart';

/// Zählt pro Film, wie viele Freunde des aktuellen Users ihn in dieser
/// Gruppe geliked haben (§7/§18 der Master-Spezifikation: "Für jede Gruppe
/// einen Zähler `friend_likes` pro Film führen"). [groupLikes] sind alle
/// Like-Swipes der Gruppe (`SwipeRepository.getGroupLikes`), [friendUids]
/// die UIDs der tatsächlichen Freunde des aktuellen Users - Likes von
/// Nicht-Freunden zählen bewusst nicht mit, auch wenn sie Mitglied derselben
/// Gruppe sind.
Map<int, int> countFriendLikes({
  required List<MovieSwipe> groupLikes,
  required Set<String> friendUids,
}) {
  final counts = <int, int>{};
  for (final swipe in groupLikes) {
    if (!friendUids.contains(swipe.uid)) continue;
    counts.update(swipe.movieId, (value) => value + 1, ifAbsent: () => 1);
  }
  return counts;
}

/// Sortiert [movies] exakt nach der in §18 vorgegebenen MVP-Formel:
/// `ORDER BY friend_likes DESC, RANDOM()` - absteigend nach der Anzahl
/// Freunde, die den Film in dieser Gruppe geliked haben, bei Gleichstand
/// (auch bei `friend_likes == 0`, dem Normalfall ohne Boost-Signal)
/// zufällig. Sortiert ausschließlich innerhalb der bereits von TMDB
/// gelieferten, gefilterten und deduplizierten Kandidaten - erzeugt, fügt
/// hinzu oder entfernt nie einen Film.
///
/// Reine, seiteneffektfreie Funktion - unabhängig von Firestore/TMDB
/// testbar. [random] ist injizierbar, damit Tests eine deterministische
/// Reihenfolge unter Gleichstand erzwingen können; ohne Angabe wird echte
/// Zufälligkeit verwendet.
///
/// Hinweis: Wird seit der vollen §7-Boost-Formel (siehe
/// [computeBoostScore]/[sortByBoostScore] unten) nicht mehr von der
/// eigentlichen Warteschlange verwendet - bleibt als eigenständige,
/// weiterhin getestete Bausteinfunktion erhalten (§18 beschreibt sie
/// ausdrücklich als den zuerst umgesetzten MVP-Schritt).
List<Movie> sortByFriendLikeBoost(
  List<Movie> movies,
  Map<int, int> friendLikeCounts, {
  Random? random,
}) {
  final rng = random ?? Random();
  final withTieBreaker = [
    for (final movie in movies) (movie: movie, tieBreaker: rng.nextDouble()),
  ];

  withTieBreaker.sort((a, b) {
    final likesA = friendLikeCounts[a.movie.tmdbId] ?? 0;
    final likesB = friendLikeCounts[b.movie.tmdbId] ?? 0;
    if (likesA != likesB) return likesB.compareTo(likesA);
    return a.tieBreaker.compareTo(b.tieBreaker);
  });

  return [for (final entry in withTieBreaker) entry.movie];
}

// Feste Gewichte aus der Beispielrechnung in §7 der Master-Spezifikation -
// wörtlich übernommen, nicht erfunden.
const _friendBoost = 40.0;
const _genreBonus = 30.0;
const _antiBoostPerGenre = -10.0;
const _ratingMultiplier = 5.0;
const _randomMax = 20.0;

/// Berechnet den vollen personalisierten Boost-Score aus §7 für einen
/// einzelnen Film:
///
/// - **Freundes-Likes** (+40 je Freund, der den Film in dieser Gruppe
///   geliked hat, [friendLikeCounts]): kumulativ pro Freund, nicht nur
///   einmalig pro Film - das erhält die bereits vor diesem Schritt
///   bestehende, getestete MVP-Priorisierung (`countFriendLikes`/
///   `sortByFriendLikeBoost`: ein Film mit zwei Freundes-Likes rangiert
///   nachweislich vor einem mit nur einem), die durch diese Erweiterung
///   nicht kaputtgehen darf. Deckt sich mit §18s Formulierung eines
///   `friend_likes`-*Zählers* pro Film.
/// - **Genre-Präferenz** (+30 flat): sobald der Film mindestens eines der
///   [topGenres] des Users trifft (die Genres mit der höchsten
///   zeitverfallsgewichteten Like-Historie, siehe `user_preferences` /
///   `functions/userPreferences.js`).
/// - **Anti-Boost** (-10 je Genre-Überschneidung): für jedes Genre des Films,
///   das der User bereits mindestens einmal disliked hat
///   ([dislikedGenres]) - kann bei mehreren überschneidenden Genres
///   entsprechend mehrfach abziehen.
/// - **Bewertung** (Rating × 5): [Movie.voteAverage] (TMDB `vote_average` -
///   dieselbe Quelle, die app-weit bereits als "Bewertung" angezeigt wird,
///   siehe z. B. `swipe_card.dart`).
/// - **Zufallskomponente** (0-20): [random] muss injiziert werden (siehe
///   [sortByBoostScore]) - reine Funktion, kein eigener Zufallszugriff hier.
///
/// Zeitbasierter Verfall ist bereits in [topGenres]/[dislikedGenres]
/// eingerechnet (serverseitig in der Cloud Function) und fließt hier nicht
/// nochmal ein.
double computeBoostScore({
  required Movie movie,
  required Map<int, int> friendLikeCounts,
  required Set<int> topGenres,
  required Map<int, int> dislikedGenres,
  required double random,
}) {
  var score = 0.0;

  score += (friendLikeCounts[movie.tmdbId] ?? 0) * _friendBoost;

  if (movie.genreIds.any(topGenres.contains)) {
    score += _genreBonus;
  }

  final overlappingDislikedGenres =
      movie.genreIds.where(dislikedGenres.containsKey).length;
  score += overlappingDislikedGenres * _antiBoostPerGenre;

  score += movie.voteAverage * _ratingMultiplier;
  score += random;

  return score;
}

/// Sortiert [movies] absteigend nach dem vollen §7-Boost-Score
/// ([computeBoostScore]) - löst [sortByFriendLikeBoost] als tatsächlich von
/// der Swipe-Warteschlange verwendete Sortierung ab (§18: "Später erweitern
/// um Genre-Präferenzen"). Reine, seiteneffektfreie Funktion; erzeugt, fügt
/// hinzu oder entfernt nie einen Film. [random] ist injizierbar für
/// deterministische Tests.
List<Movie> sortByBoostScore(
  List<Movie> movies, {
  required Map<int, int> friendLikeCounts,
  required Set<int> topGenres,
  required Map<int, int> dislikedGenres,
  Random? random,
}) {
  final rng = random ?? Random();
  final withScore = [
    for (final movie in movies)
      (
        movie: movie,
        score: computeBoostScore(
          movie: movie,
          friendLikeCounts: friendLikeCounts,
          topGenres: topGenres,
          dislikedGenres: dislikedGenres,
          random: rng.nextDouble() * _randomMax,
        ),
      ),
  ];

  withScore.sort((a, b) => b.score.compareTo(a.score));

  return [for (final entry in withScore) entry.movie];
}
