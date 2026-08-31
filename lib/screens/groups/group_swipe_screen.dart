import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../components/movies/swipe_card.dart';
import '../../models/movie.dart';
import '../../models/movie_match.dart';
import '../../providers/group_provider.dart';
import '../../providers/match_provider.dart';
import '../../providers/movie_filter_provider.dart';
import '../../providers/swipe_action_controller.dart';
import '../../providers/swipe_queue_controller.dart';
import '../../providers/tmdb_provider.dart';
import '../../services/tmdb_image_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/group_error_translator.dart';
import '../../utils/tmdb_error_translator.dart';
import '../movies/movie_detail_screen.dart';
import '../movies/movie_filter_screen.dart';

/// Echte Gruppen-Swipe-Oberfläche: Filme aus TMDB Discover, gefiltert um
/// bereits vom aktuellen User bewertete Filme dieser Gruppe. Speichert Like/
/// Dislike/Skip/Watchlist dauerhaft in Firestore - Skip und Watchlist
/// ("Vielleicht später", unten bzw. oben) blenden den Film nur für diesen
/// User aus, zählen nie als Like oder Dislike und beeinflussen nie die
/// Match-Erkennung oder die Swipes anderer Mitglieder. Reagiert live auf neu
/// entstandene Matches
/// (serverseitig per Cloud Function erkannt, siehe `functions/index.js`) mit
/// einer "Match! 🍿"-Anzeige. Noch kein Chat.
class GroupSwipeScreen extends ConsumerStatefulWidget {
  const GroupSwipeScreen({super.key, required this.groupId});

  final String groupId;

  @override
  ConsumerState<GroupSwipeScreen> createState() => _GroupSwipeScreenState();
}

class _GroupSwipeScreenState extends ConsumerState<GroupSwipeScreen> {
  final _cardKey = GlobalKey<SwipeCardState>();

  // Bereits bekannte Match-Filme dieser Session - verhindert, dass beim
  // Öffnen des Screens für längst bestehende Matches erneut gefeiert wird;
  // nur echt *neu* hinzugekommene Matches lösen die Anzeige aus.
  final Set<int> _knownMatchMovieIds = {};
  bool _matchesInitialized = false;

  void _handleSwiped(SwipeCardDirection direction, Movie movie) {
    final notifier = ref.read(swipeActionControllerProvider(widget.groupId).notifier);
    switch (direction) {
      case SwipeCardDirection.like:
        notifier.like(movie.tmdbId);
      case SwipeCardDirection.dislike:
        notifier.dislike(movie.tmdbId);
      case SwipeCardDirection.skip:
        notifier.skip(movie.tmdbId);
      case SwipeCardDirection.watchlist:
        notifier.watchlist(movie.tmdbId);
    }
  }

  void _handleMatchesUpdate(List<MovieMatch> matches) {
    final currentIds = matches.map((m) => m.movieId).toSet();
    if (!_matchesInitialized) {
      _matchesInitialized = true;
      _knownMatchMovieIds.addAll(currentIds);
      return;
    }
    final newIds = currentIds.difference(_knownMatchMovieIds);
    _knownMatchMovieIds.addAll(currentIds);
    for (final movieId in newIds) {
      showDialog<void>(
        context: context,
        builder: (dialogContext) => _MatchDialog(movieId: movieId),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final queueAsync = ref.watch(swipeQueueControllerProvider(widget.groupId));
    final actionState = ref.watch(swipeActionControllerProvider(widget.groupId));
    final groupName = ref.watch(groupProvider(widget.groupId)).value?.name;
    final activeFilterCount =
        ref.watch(movieFilterControllerProvider(widget.groupId)).activeCount;

    ref.listen(swipeActionControllerProvider(widget.groupId), (previous, next) {
      next.whenOrNull(
        error: (error, _) => ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(translateGroupError(error)))),
      );
    });

    ref.listen(groupMatchesProvider(widget.groupId), (previous, next) {
      next.whenData(_handleMatchesUpdate);
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(groupName == null ? 'Swipe' : 'Swipe · $groupName'),
        actions: [
          IconButton(
            tooltip: 'Filter',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => MovieFilterScreen(groupId: widget.groupId)),
            ),
            icon: Badge(
              label: Text('$activeFilterCount'),
              isLabelVisible: activeFilterCount > 0,
              child: const Icon(Icons.tune),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: queueAsync.when(
          data: (queue) {
            if (queue.isEmpty) {
              return const _EmptyQueueState();
            }
            final movie = queue.first;
            final isBusy = actionState.isLoading;

            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Expanded(
                    child: Center(
                      child: GestureDetector(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => MovieDetailScreen(tmdbId: movie.tmdbId)),
                        ),
                        child: SwipeCard(
                          key: _cardKey,
                          movie: movie,
                          isEnabled: !isBusy,
                          onSwiped: (direction) => _handleSwiped(direction, movie),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _SwipeActionButton(
                        icon: Icons.close_rounded,
                        color: Colors.redAccent,
                        enabled: !isBusy,
                        onPressed: () => _cardKey.currentState?.triggerDislike(),
                      ),
                      _SwipeActionButton(
                        icon: Icons.watch_later_outlined,
                        color: Colors.amber,
                        enabled: !isBusy,
                        onPressed: () => _cardKey.currentState?.triggerSkip(),
                      ),
                      _SwipeActionButton(
                        icon: Icons.bookmark_add_outlined,
                        color: Colors.lightBlueAccent,
                        enabled: !isBusy,
                        onPressed: () => _cardKey.currentState?.triggerWatchlist(),
                      ),
                      _SwipeActionButton(
                        icon: Icons.favorite,
                        color: AppColors.accentSecondary,
                        enabled: !isBusy,
                        onPressed: () => _cardKey.currentState?.triggerLike(),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator(color: AppColors.accent)),
          error: (error, _) => _ErrorState(
            message: translateTmdbError(error),
            onRetry: () => ref.read(swipeQueueControllerProvider(widget.groupId).notifier).retry(),
          ),
        ),
      ),
    );
  }
}

class _SwipeActionButton extends StatelessWidget {
  const _SwipeActionButton({
    required this.icon,
    required this.color,
    required this.enabled,
    required this.onPressed,
  });

  final IconData icon;
  final Color color;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceVariant,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: enabled ? onPressed : null,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Icon(icon, color: enabled ? color : AppColors.textSecondary, size: 32),
        ),
      ),
    );
  }
}

class _EmptyQueueState extends StatelessWidget {
  const _EmptyQueueState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.movie_filter_outlined, size: 56, color: AppColors.textSecondary),
            const SizedBox(height: 16),
            const Text(
              'Keine weiteren Filme verfügbar.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Match! 🍿"-Dialog mit Poster - wird angezeigt, sobald in
/// `groupMatchesProvider` ein neues Match-Dokument auftaucht (serverseitig
/// von der Cloud Function erzeugt, siehe `functions/index.js`).
class _MatchDialog extends ConsumerWidget {
  const _MatchDialog({required this.movieId});

  final int movieId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final movieAsync = ref.watch(movieDetailsProvider(movieId));

    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Match! 🍿', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            movieAsync.when(
              data: (movie) {
                final posterUrl = TmdbImageService.posterUrl(movie.posterPath);
                return Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: SizedBox(
                        width: 140,
                        height: 210,
                        child: posterUrl == null
                            ? Container(
                                color: AppColors.surfaceVariant,
                                child: const Icon(Icons.movie_outlined, color: AppColors.textSecondary),
                              )
                            : Image.network(posterUrl, fit: BoxFit.cover),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      movie.title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                    ),
                  ],
                );
              },
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(color: AppColors.accent),
              ),
              error: (error, _) => const Text(
                'Eure Gruppe hat einen gemeinsamen Film gefunden.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Weiter swipen'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => MovieDetailScreen(tmdbId: movieId)),
                    );
                  },
                  child: const Text('Ansehen'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('Erneut versuchen')),
          ],
        ),
      ),
    );
  }
}
