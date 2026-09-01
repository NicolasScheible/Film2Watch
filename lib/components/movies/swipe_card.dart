import 'package:flutter/material.dart';

import '../../models/movie.dart';
import '../../services/tmdb_image_service.dart';
import '../../theme/app_theme.dart';

enum SwipeCardDirection { like, dislike, skip, watchlist, superSwipe }

/// Eine zieh-/wischbare Filmkarte. Buttons steuern dieselbe Karte über
/// [SwipeCardState.triggerLike]/[SwipeCardState.triggerDislike]/
/// [SwipeCardState.triggerSkip]/[SwipeCardState.triggerWatchlist] - dieselbe
/// Animation und derselbe [onSwiped]-Aufruf wie bei einer echten Geste,
/// keine doppelte Business-Logik. Horizontal: rechts = Like, links =
/// Dislike. Vertikal: unten = Skip/"Vielleicht später", oben = Watchlist/
/// "Vielleicht später" - beide blenden den Film laut Produktspezifikation
/// nur für den aktuellen Nutzer aus, das setzt ausschließlich [onSwiped]
/// um, ohne eigene Ausblend-Logik hier in der Karte.
///
/// [SwipeCardState.triggerSuperSwipe] (§6/§15, Premium-Feature) hat
/// bewusst KEINE eigene Zieh-Geste - alle vier Zug-Richtungen sind bereits
/// mit Like/Dislike/Skip/Watchlist belegt, eine Diagonale würde mit der
/// Badge-Anzeige der bestehenden Richtungen kollidieren. Stattdessen ein
/// eigenständiger Skalier-/Fade-Effekt (siehe `_superSwiping`), nur über
/// einen dedizierten Button auslösbar.
class SwipeCard extends StatefulWidget {
  const SwipeCard({
    super.key,
    required this.movie,
    required this.onSwiped,
    this.isEnabled = true,
  });

  final Movie movie;
  final ValueChanged<SwipeCardDirection> onSwiped;
  final bool isEnabled;

  @override
  State<SwipeCard> createState() => SwipeCardState();
}

class SwipeCardState extends State<SwipeCard> with SingleTickerProviderStateMixin {
  static const _swipeThreshold = 120.0;

  late final AnimationController _controller;
  Animation<Offset>? _animation;
  Offset _dragOffset = Offset.zero;
  bool _dragging = false;
  // Super Swipe animiert nicht über [_dragOffset] (siehe Klassendoku) -
  // eigener Zustand, damit die vier bestehenden Richtungs-Badges während
  // dieser Animation unverändert bei Opazität 0 bleiben.
  bool _superSwiping = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));
  }

  @override
  void didUpdateWidget(covariant SwipeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.movie.tmdbId != widget.movie.tmdbId) {
      _controller.stop();
      _dragOffset = Offset.zero;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void triggerLike() => _fling(SwipeCardDirection.like);

  void triggerDislike() => _fling(SwipeCardDirection.dislike);

  void triggerSkip() => _fling(SwipeCardDirection.skip);

  void triggerWatchlist() => _fling(SwipeCardDirection.watchlist);

  /// Löst einen Super Swipe aus (§6/§15, Premium-Feature - die eigentliche
  /// Premium-Prüfung passiert serverseitig in `SwipeService.superSwipeMovie`/
  /// den Firestore Rules, nicht hier). Eigener Skalier-/Fade-Effekt statt
  /// eines gerichteten Flings, siehe Klassendoku.
  void triggerSuperSwipe() {
    if (!widget.isEnabled || _superSwiping) return;
    setState(() => _superSwiping = true);
    _controller
      ..reset()
      ..forward().whenComplete(() {
        widget.onSwiped(SwipeCardDirection.superSwipe);
        if (mounted) setState(() => _superSwiping = false);
      });
  }

  void _fling(SwipeCardDirection direction) {
    if (!widget.isEnabled || _superSwiping) return;
    final size = MediaQuery.of(context).size;
    final Offset target;
    switch (direction) {
      case SwipeCardDirection.like:
        target = Offset(size.width * 1.2, _dragOffset.dy);
      case SwipeCardDirection.dislike:
        target = Offset(-size.width * 1.2, _dragOffset.dy);
      case SwipeCardDirection.skip:
        target = Offset(_dragOffset.dx, size.height * 1.2);
      case SwipeCardDirection.watchlist:
        target = Offset(_dragOffset.dx, -size.height * 1.2);
      case SwipeCardDirection.superSwipe:
        // Wird nie über diesen Pfad ausgelöst - Super Swipe hat keine
        // Zug-Geste (siehe Klassendoku) und läuft ausschließlich über
        // [triggerSuperSwipe], nie über [_fling]/[_onPanEnd].
        throw StateError('Super Swipe hat keine Zug-Geste.');
    }
    _runAnimation(target, onComplete: () => widget.onSwiped(direction));
  }

  void _runAnimation(Offset target, {VoidCallback? onComplete}) {
    _animation = Tween<Offset>(begin: _dragOffset, end: target).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    )..addListener(() => setState(() => _dragOffset = _animation!.value));
    _controller
      ..reset()
      ..forward().whenComplete(() {
        if (onComplete != null) onComplete();
      });
  }

  void _onPanStart(DragStartDetails details) {
    if (!widget.isEnabled || _superSwiping) return;
    _controller.stop();
    _dragging = true;
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (!widget.isEnabled || !_dragging) return;
    setState(() => _dragOffset += details.delta);
  }

  void _onPanEnd(DragEndDetails details) {
    if (!widget.isEnabled || !_dragging) return;
    _dragging = false;
    final horizontal = _dragOffset.dx.abs();
    final vertical = _dragOffset.dy.abs();

    if (vertical > _swipeThreshold && vertical >= horizontal) {
      // Vorwiegend vertikal gezogen - Runter = Skip, Hoch = Watchlist
      // (beide "Vielleicht später", nur die Richtung unterscheidet sie).
      _fling(_dragOffset.dy > 0 ? SwipeCardDirection.skip : SwipeCardDirection.watchlist);
    } else if (horizontal > _swipeThreshold) {
      _fling(_dragOffset.dx > 0 ? SwipeCardDirection.like : SwipeCardDirection.dislike);
    } else {
      _runAnimation(Offset.zero);
    }
  }

  @override
  Widget build(BuildContext context) {
    final angle = (_dragOffset.dx / 800).clamp(-0.4, 0.4);
    final likeOpacity = (_dragOffset.dx / _swipeThreshold).clamp(0.0, 1.0);
    final dislikeOpacity = (-_dragOffset.dx / _swipeThreshold).clamp(0.0, 1.0);
    final skipOpacity = (_dragOffset.dy / _swipeThreshold).clamp(0.0, 1.0);
    final watchlistOpacity = (-_dragOffset.dy / _swipeThreshold).clamp(0.0, 1.0);

    final card = GestureDetector(
      onPanStart: _onPanStart,
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
      child: Transform.translate(
        offset: _dragOffset,
        child: Transform.rotate(
          angle: angle,
          child: Stack(
            children: [
              _SwipeCardContent(movie: widget.movie),
              Positioned(
                top: 28,
                left: 24,
                child: _DirectionBadge(label: 'LIKE', color: AppColors.accentSecondary, opacity: likeOpacity),
              ),
              Positioned(
                top: 28,
                right: 24,
                child: _DirectionBadge(label: 'NOPE', color: Colors.redAccent, opacity: dislikeOpacity),
              ),
              Positioned(
                bottom: 28,
                left: 0,
                right: 0,
                child: Center(
                  child: _DirectionBadge(label: 'SKIP', color: Colors.amber, opacity: skipOpacity),
                ),
              ),
              Positioned(
                top: 28,
                left: 0,
                right: 0,
                child: Center(
                  child: _DirectionBadge(
                    label: 'WATCHLIST',
                    color: Colors.lightBlueAccent,
                    opacity: watchlistOpacity,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (!_superSwiping) return card;

    // Super Swipe: eigenständiger Skalier-/Fade-Effekt statt eines
    // gerichteten Flings (siehe Klassendoku) - `_dragOffset` bleibt dabei
    // bei Zero, die vier Richtungs-Badges oben bleiben unsichtbar.
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        return Opacity(
          opacity: (1 - t).clamp(0.0, 1.0),
          child: Transform.scale(
            scale: 1 + t * 0.15,
            child: Stack(
              alignment: Alignment.center,
              children: [
                child!,
                _DirectionBadge(label: 'SUPER SWIPE', color: Colors.purpleAccent, opacity: t),
              ],
            ),
          ),
        );
      },
      child: card,
    );
  }
}

class _DirectionBadge extends StatelessWidget {
  const _DirectionBadge({required this.label, required this.color, required this.opacity});

  final String label;
  final Color color;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: color, width: 3),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 22, letterSpacing: 1),
        ),
      ),
    );
  }
}

class _SwipeCardContent extends StatelessWidget {
  const _SwipeCardContent({required this.movie});

  final Movie movie;

  @override
  Widget build(BuildContext context) {
    final posterUrl = TmdbImageService.posterUrl(movie.posterPath, size: TmdbImageSize.w780);

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: AspectRatio(
        aspectRatio: 2 / 3,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(
              color: AppColors.surfaceVariant,
              child: posterUrl == null
                  ? const Center(
                      child: Icon(Icons.movie_outlined, color: AppColors.textSecondary, size: 48),
                    )
                  : Image.network(
                      posterUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => const Center(
                        child: Icon(Icons.broken_image_outlined, color: AppColors.textSecondary),
                      ),
                    ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
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
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 22,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (movie.releaseDate != null)
                          Text(
                            '${movie.releaseDate!.year}',
                            style: const TextStyle(color: Colors.white70),
                          ),
                        if (movie.voteAverage > 0) ...[
                          const SizedBox(width: 12),
                          const Icon(Icons.star, size: 16, color: AppColors.accentSecondary),
                          const SizedBox(width: 4),
                          Text(
                            movie.voteAverage.toStringAsFixed(1),
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ],
                      ],
                    ),
                    if (movie.genres.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final genre in movie.genres.take(3))
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white24,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(genre, style: const TextStyle(color: Colors.white, fontSize: 12)),
                            ),
                        ],
                      ),
                    ],
                    if (movie.overview.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        movie.overview,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70, height: 1.3),
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
  }
}
