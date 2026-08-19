import 'movie.dart';

/// Eine paginierte TMDB-Ergebnisseite (Discover/Search).
class MoviePage {
  const MoviePage({
    required this.movies,
    required this.page,
    required this.totalPages,
    required this.totalResults,
  });

  final List<Movie> movies;
  final int page;
  final int totalPages;
  final int totalResults;

  bool get hasNextPage => page < totalPages;
}
