import 'package:flutter/material.dart';

import '../../models/movie.dart';
import '../../services/tmdb_image_service.dart';
import '../../theme/app_theme.dart';

/// Filmkarte mit Poster, Titel und Bewertung - für Browse-/Suchergebnisse.
class MoviePosterCard extends StatelessWidget {
  const MoviePosterCard({super.key, required this.movie, required this.onTap});

  final Movie movie;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final posterUrl = TmdbImageService.posterUrl(movie.posterPath);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 2 / 3,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                color: AppColors.surfaceVariant,
                child: posterUrl == null
                    ? const Center(
                        child: Icon(Icons.movie_outlined, color: AppColors.textSecondary, size: 32),
                      )
                    : Image.network(
                        posterUrl,
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          return const Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) => const Center(
                          child: Icon(Icons.broken_image_outlined, color: AppColors.textSecondary),
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            movie.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          if (movie.voteAverage > 0)
            Row(
              children: [
                const Icon(Icons.star, size: 14, color: AppColors.accentSecondary),
                const SizedBox(width: 4),
                Text(
                  movie.voteAverage.toStringAsFixed(1),
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
