import '../models/movie.dart';

/// Hängt [incoming] an [current] an, ohne Filme zu duplizieren, die (per
/// `tmdbId`) bereits enthalten sind - wichtig, da TMDB-Discover/Search-Seiten
/// sich bei paralleler Popularitätsänderung theoretisch überschneiden können.
List<Movie> mergeUniqueMovies(List<Movie> current, List<Movie> incoming) {
  final seenIds = current.map((movie) => movie.tmdbId).toSet();
  final merged = [...current];
  for (final movie in incoming) {
    if (seenIds.add(movie.tmdbId)) {
      merged.add(movie);
    }
  }
  return merged;
}
