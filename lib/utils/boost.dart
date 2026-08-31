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
