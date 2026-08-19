import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/movie.dart';
import '../utils/movie_list_utils.dart';
import 'tmdb_provider.dart';

/// Sucht Filme bei TMDB und lädt weitere Seiten dedupliziert nach.
class MovieSearchController extends AsyncNotifier<List<Movie>> {
  String _query = '';
  int _page = 0;
  bool _hasNextPage = false;

  @override
  List<Movie> build() => const [];

  Future<void> search(String query) async {
    if (state.isLoading) return;
    _query = query.trim();
    _page = 0;
    _hasNextPage = true;

    if (_query.isEmpty) {
      state = const AsyncData([]);
      return;
    }

    state = const AsyncLoading<List<Movie>>();
    state = await AsyncValue.guard(() => _loadPage(1));
  }

  Future<void> loadNextPage() async {
    if (state.isLoading || !_hasNextPage || _query.isEmpty) return;
    final current = state.value ?? const [];
    state = const AsyncLoading<List<Movie>>();
    state = await AsyncValue.guard(() => _loadPage(_page + 1, existing: current));
  }

  Future<List<Movie>> _loadPage(int page, {List<Movie> existing = const []}) async {
    final result =
        await ref.read(movieRepositoryProvider).searchMovies(query: _query, page: page);
    _page = result.page;
    _hasNextPage = result.hasNextPage;
    return mergeUniqueMovies(existing, result.movies);
  }
}

final movieSearchControllerProvider =
    AsyncNotifierProvider<MovieSearchController, List<Movie>>(MovieSearchController.new);
