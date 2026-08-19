import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/tmdb_provider.dart';
import '../../services/tmdb_image_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/tmdb_error_translator.dart';

/// Echte TMDB-Filmdetails - dient in diesem Schritt nur zur Verifikation der
/// Integration, noch keine Swipe-/Match-Aktionen.
class MovieDetailScreen extends ConsumerWidget {
  const MovieDetailScreen({super.key, required this.tmdbId});

  final int tmdbId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final movieAsync = ref.watch(movieDetailsProvider(tmdbId));

    return Scaffold(
      body: movieAsync.when(
        data: (movie) {
          final backdropUrl = TmdbImageService.backdropUrl(movie.backdropPath);
          final posterUrl = TmdbImageService.posterUrl(movie.posterPath);

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 220,
                pinned: true,
                backgroundColor: AppColors.background,
                flexibleSpace: FlexibleSpaceBar(
                  background: backdropUrl == null
                      ? Container(color: AppColors.surfaceVariant)
                      : Image.network(
                          backdropUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              Container(color: AppColors.surfaceVariant),
                        ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: SizedBox(
                              width: 96,
                              height: 144,
                              child: posterUrl == null
                                  ? Container(
                                      color: AppColors.surfaceVariant,
                                      child: const Icon(Icons.movie_outlined, color: AppColors.textSecondary),
                                    )
                                  : Image.network(
                                      posterUrl,
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) =>
                                          Container(color: AppColors.surfaceVariant),
                                    ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(movie.title, style: Theme.of(context).textTheme.headlineSmall),
                                if (movie.releaseDate != null || movie.runtime != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      [
                                        if (movie.releaseDate != null) '${movie.releaseDate!.year}',
                                        if (movie.runtime != null) '${movie.runtime} Min.',
                                      ].join(' · '),
                                      style: const TextStyle(color: AppColors.textSecondary),
                                    ),
                                  ),
                                if (movie.voteAverage > 0)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.star, size: 18, color: AppColors.accentSecondary),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${movie.voteAverage.toStringAsFixed(1)} (${movie.voteCount})',
                                          style: const TextStyle(color: AppColors.textPrimary),
                                        ),
                                      ],
                                    ),
                                  ),
                                if (movie.genres.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: [
                                        for (final genre in movie.genres)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: AppColors.surfaceVariant,
                                              borderRadius: BorderRadius.circular(20),
                                            ),
                                            child: Text(
                                              genre,
                                              style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (movie.overview.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        Text('Beschreibung', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Text(movie.overview, style: const TextStyle(color: AppColors.textSecondary, height: 1.4)),
                      ],
                      const SizedBox(height: 20),
                      _WatchProvidersSection(tmdbId: tmdbId),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
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
    );
  }
}

class _WatchProvidersSection extends ConsumerWidget {
  const _WatchProvidersSection({required this.tmdbId});

  final int tmdbId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final providersAsync = ref.watch(movieWatchProvidersProvider(tmdbId));

    return providersAsync.when(
      data: (providers) {
        if (providers.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Verfügbar bei', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SizedBox(
              height: 56,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: providers.length,
                separatorBuilder: (context, index) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final logoUrl = TmdbImageService.providerLogoUrl(providers[index].logoPath);
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: logoUrl == null
                          ? Container(color: AppColors.surfaceVariant)
                          : Image.network(
                              logoUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  Container(color: AppColors.surfaceVariant),
                            ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (error, _) => const SizedBox.shrink(),
    );
  }
}
