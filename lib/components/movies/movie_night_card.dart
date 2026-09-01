import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/movie_night.dart';
import '../../providers/tmdb_provider.dart';
import '../../services/tmdb_image_service.dart';
import '../../theme/app_theme.dart';

String formatMovieNightSchedule(DateTime dt) {
  final day = dt.day.toString().padLeft(2, '0');
  final month = dt.month.toString().padLeft(2, '0');
  final hour = dt.hour.toString().padLeft(2, '0');
  final minute = dt.minute.toString().padLeft(2, '0');
  return '$day.$month.${dt.year}, $hour:$minute Uhr';
}

/// Eine Filmabend-Karte (§12: "Filmabend planen") - Termin, Plattform und,
/// falls gesetzt, der zugehörige Match-Film. Zeigt niemals eine
/// Teilnahme-/RSVP-Liste (mit dem Produktverantwortlichen ausdrücklich
/// zurückgestellt).
class MovieNightCard extends ConsumerWidget {
  const MovieNightCard({
    super.key,
    required this.movieNight,
    this.trailing,
    this.onTap,
  });

  final MovieNight movieNight;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final providers = ref.watch(watchProviderListProvider).value ?? const [];
    final matchingPlatforms = providers.where((p) => p.providerId == movieNight.platformId);
    final platform = matchingPlatforms.isEmpty ? null : matchingPlatforms.first;
    final movieId = movieNight.movieId;

    return Material(
      color: AppColors.surfaceVariant,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.event_outlined, color: AppColors.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      formatMovieNightSchedule(movieNight.scheduledAt),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (platform?.logoPath != null) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: Image.network(
                              TmdbImageService.providerLogoUrl(platform!.logoPath) ?? '',
                              width: 18,
                              height: 18,
                              errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Text(
                          platform?.providerName ?? 'Plattform',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                        ),
                      ],
                    ),
                    if (movieId != null) _MovieTitleLabel(movieId: movieId),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}

/// Nur der Filmtitel, aus TMDB nachgeladen (Firestore speichert nur die
/// `movie_id`, keine vollständigen Filmdaten).
class _MovieTitleLabel extends ConsumerWidget {
  const _MovieTitleLabel({required this.movieId});

  final int movieId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final movieAsync = ref.watch(movieDetailsProvider(movieId));
    return movieAsync.when(
      data: (movie) => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(
          children: [
            const Icon(Icons.local_movies_outlined, size: 14, color: AppColors.textSecondary),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                movie.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
      loading: () => const SizedBox.shrink(),
      error: (error, _) => const SizedBox.shrink(),
    );
  }
}
