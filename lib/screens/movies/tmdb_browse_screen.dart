import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../components/movies/movie_poster_card.dart';
import '../../models/movie.dart';
import '../../providers/discover_movies_controller.dart';
import '../../providers/movie_search_controller.dart';
import '../../theme/app_theme.dart';
import '../../utils/tmdb_error_translator.dart';
import 'movie_detail_screen.dart';

/// Technische Verifikationsseite für die TMDB-Integration: Suche und
/// Beliebtheits-Übersicht mit echten TMDB-Daten. Kein Swipe, keine Matches -
/// nur zur Prüfung, dass die Film-Datenbasis funktioniert.
class TmdbBrowseScreen extends ConsumerStatefulWidget {
  const TmdbBrowseScreen({super.key});

  @override
  ConsumerState<TmdbBrowseScreen> createState() => _TmdbBrowseScreenState();
}

class _TmdbBrowseScreenState extends ConsumerState<TmdbBrowseScreen> {
  final _searchController = TextEditingController();
  bool get _isSearching => _searchController.text.trim().isNotEmpty;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() {});
    ref.read(movieSearchControllerProvider.notifier).search(value);
  }

  @override
  Widget build(BuildContext context) {
    final moviesAsync =
        _isSearching ? ref.watch(movieSearchControllerProvider) : ref.watch(discoverMoviesControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('TMDB Test / Browse')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Film suchen ...',
                hintStyle: const TextStyle(color: AppColors.textSecondary),
                prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary),
                filled: true,
                fillColor: AppColors.surfaceVariant,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: moviesAsync.when(
                data: (movies) => _MovieGrid(
                  movies: movies,
                  onLoadMore: () => _isSearching
                      ? ref.read(movieSearchControllerProvider.notifier).loadNextPage()
                      : ref.read(discoverMoviesControllerProvider.notifier).loadNextPage(),
                ),
                loading: () => const Center(child: CircularProgressIndicator(color: AppColors.accent)),
                error: (error, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      translateTmdbError(error),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MovieGrid extends StatelessWidget {
  const _MovieGrid({required this.movies, required this.onLoadMore});

  final List<Movie> movies;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (movies.isEmpty) {
      return const Center(
        child: Text('Keine Filme gefunden.', style: TextStyle(color: AppColors.textSecondary)),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.pixels >= notification.metrics.maxScrollExtent - 200) {
          onLoadMore();
        }
        return false;
      },
      child: GridView.builder(
        padding: const EdgeInsets.only(bottom: 16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 0.55,
          crossAxisSpacing: 12,
          mainAxisSpacing: 16,
        ),
        itemCount: movies.length,
        itemBuilder: (context, index) {
          final movie = movies[index];
          return MoviePosterCard(
            movie: movie,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => MovieDetailScreen(tmdbId: movie.tmdbId)),
            ),
          );
        },
      ),
    );
  }
}
