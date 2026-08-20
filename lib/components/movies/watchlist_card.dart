import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/tmdb_provider.dart';
import '../../services/tmdb_image_service.dart';
import '../../theme/app_theme.dart';

/// Eine Watchlist-Karte: Poster im Vordergrund, Titel/Jahr/Bewertung/Genres
/// als Overlay, plus ein Badge oben rechts, das den gruppenweiten
/// Watchlist-Abgleich zeigt ("Du hast vorgemerkt" bzw. "2/4 vorgemerkt").
/// Bewusst nach demselben Muster wie `MatchCard` aufgebaut (gleiches
/// Dark-Theme, gleiche TMDB-Lade-/Fehlerzustände, gleiche
/// Poster-Overlay-Struktur) statt einer neuen Design-Sprache. Nimmt bewusst
/// nur die `movieId` entgegen statt eines vollständigen Modells - die
/// Watchlist-Zuordnung selbst (`WatchlistEntry`) lebt ausschließlich in
/// `swipe_provider.dart`, hier wird nur noch angezeigt. Lädt TMDB
/// unabhängig pro Karte, damit ein einzelner Ladefehler nicht die gesamte
/// Liste blockiert.
class WatchlistCard extends ConsumerWidget {
  const WatchlistCard({
    super.key,
    required this.movieId,
    required this.badgeLabel,
    required this.onTap,
  });

  final int movieId;
  final String badgeLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final movieAsync = ref.watch(movieDetailsProvider(movieId));

    // Bewusst keine eigene feste Breite - siehe `MatchCard` für die
    // ausführliche Begründung (dieselbe Karte in horizontaler Liste und
    // Grid nutzbar).
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
                    top: 8,
                    left: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        badgeLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.lightBlueAccent,
                          fontWeight: FontWeight.w700,
                          fontSize: 10,
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
