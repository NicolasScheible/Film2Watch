import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../components/movies/swipe_card.dart';
import '../../models/movie.dart';
import '../../providers/group_provider.dart';
import '../../providers/swipe_action_controller.dart';
import '../../providers/swipe_queue_controller.dart';
import '../../theme/app_theme.dart';
import '../../utils/group_error_translator.dart';
import '../../utils/tmdb_error_translator.dart';
import '../movies/movie_detail_screen.dart';

/// Echte Gruppen-Swipe-Oberfläche: Filme aus TMDB Discover, gefiltert um
/// bereits vom aktuellen User bewertete Filme dieser Gruppe. Speichert Like/
/// Dislike dauerhaft in Firestore. Noch keine Match-Auswertung, kein Chat.
class GroupSwipeScreen extends ConsumerStatefulWidget {
  const GroupSwipeScreen({super.key, required this.groupId});

  final String groupId;

  @override
  ConsumerState<GroupSwipeScreen> createState() => _GroupSwipeScreenState();
}

class _GroupSwipeScreenState extends ConsumerState<GroupSwipeScreen> {
  final _cardKey = GlobalKey<SwipeCardState>();

  void _handleSwiped(SwipeCardDirection direction, Movie movie) {
    final notifier = ref.read(swipeActionControllerProvider(widget.groupId).notifier);
    if (direction == SwipeCardDirection.like) {
      notifier.like(movie.tmdbId);
    } else {
      notifier.dislike(movie.tmdbId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final queueAsync = ref.watch(swipeQueueControllerProvider(widget.groupId));
    final actionState = ref.watch(swipeActionControllerProvider(widget.groupId));
    final groupName = ref.watch(groupProvider(widget.groupId)).value?.name;

    ref.listen(swipeActionControllerProvider(widget.groupId), (previous, next) {
      next.whenOrNull(
        error: (error, _) => ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(translateGroupError(error)))),
      );
    });

    return Scaffold(
      appBar: AppBar(title: Text(groupName == null ? 'Swipe' : 'Swipe · $groupName')),
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
