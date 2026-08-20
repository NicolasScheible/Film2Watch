import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/movie_match.dart';
import '../../providers/tmdb_provider.dart';
import '../../services/tmdb_image_service.dart';
import '../../theme/app_theme.dart';

/// Eine Match-Karte: Poster im Vordergrund, Titel/Jahr/Bewertung/Genres als
/// Overlay. Wird sowohl in der Match-Liste einer einzelnen Gruppe
/// (`GroupDetailScreen`) als auch in der gruppenübergreifenden Match-Liste
/// (`MatchesScreen`) verwendet. Die eigentlichen Filmdaten kommen live über
/// TMDB (`movieDetailsProvider`) - Firestore liefert nur die movieId. Lädt
/// TMDB unabhängig pro Karte, damit ein einzelner Ladefehler nicht die
/// gesamte Liste blockiert (siehe `movieAsync.when` unten).
class MatchCard extends ConsumerWidget {
  const MatchCard({super.key, required this.match, required this.onTap});

  final MovieMatch match;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final movieAsync = ref.watch(movieDetailsProvider(match.movieId));

    // Bewusst keine eigene feste Breite: die Karte füllt den vom
    // Aufrufer vorgegebenen Platz (fester Breite in einer horizontalen
    // Liste, Zellenbreite in einem Grid) - so passt dieselbe Karte in beide
    // Verwendungskontexte, ohne Layout-Konflikte.
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: movieAsync.when(
        data: (movie) {
          final posterUrl = TmdbImageService.posterUrl(movie.posterPath);
          return ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(
              aspectRatio: 2 / 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    color: AppColors.surfaceVariant,
                    child: posterUrl == null
                        ? const Center(
                            child: Icon(
                              Icons.movie_outlined,
                              color: AppColors.textSecondary,
                            ),
                          )
                        : Image.network(
                            posterUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const Center(
                                  child: Icon(
                                    Icons.broken_image_outlined,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                          ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(10, 24, 10, 10),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black87],
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            movie.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          if (movie.releaseDate != null ||
                              movie.voteAverage > 0) ...[
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                if (movie.releaseDate != null)
                                  Text(
                                    '${movie.releaseDate!.year}',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 11,
                                    ),
                                  ),
                                if (movie.voteAverage > 0) ...[
                                  if (movie.releaseDate != null)
                                    const SizedBox(width: 8),
                                  const Icon(
                                    Icons.star,
                                    size: 13,
                                    color: AppColors.accentSecondary,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    movie.voteAverage.toStringAsFixed(1),
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                          if (movie.genres.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              movie.genres.take(2).join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
        loading: () => AspectRatio(
          aspectRatio: 2 / 3,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              color: AppColors.surfaceVariant,
              child: const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.accent,
                  ),
                ),
              ),
            ),
          ),
        ),
        error: (error, _) => AspectRatio(
          aspectRatio: 2 / 3,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              color: AppColors.surfaceVariant,
              child: const Center(
                child: Icon(
                  Icons.error_outline,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
