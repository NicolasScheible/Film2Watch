import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/movie.dart';
import '../utils/movie_list_utils.dart';
import 'tmdb_provider.dart';

/// Lädt TMDB-Discover-Ergebnisse seitenweise und hängt neue Seiten dedupliziert
/// an (siehe [mergeUniqueMovies]). Keine Infinite-Swipe-Mechanik - nur die
/// Grundlage, mehrere Seiten sauber zu laden.
class DiscoverMoviesController extends AsyncNotifier<List<Movie>> {
  int _page = 0;
  bool _hasNextPage = true;

  @override
  Future<List<Movie>> build() async {
    _page = 0;
    _hasNextPage = true;
    return _loadPage(1);
  }

  Future<void> loadNextPage() async {
    if (state.isLoading || !_hasNextPage) return;
    final current = state.value ?? const [];
    state = const AsyncLoading<List<Movie>>();
    state = await AsyncValue.guard(() => _loadPage(_page + 1, existing: current));
  }

  Future<List<Movie>> _loadPage(int page, {List<Movie> existing = const []}) async {
    final result = await ref.read(movieRepositoryProvider).discoverMovies(page: page);
    _page = result.page;
    _hasNextPage = result.hasNextPage;
    return mergeUniqueMovies(existing, result.movies);
  }
}

final discoverMoviesControllerProvider =
    AsyncNotifierProvider<DiscoverMoviesController, List<Movie>>(DiscoverMoviesController.new);
