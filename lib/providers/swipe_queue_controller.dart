import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/movie.dart';
import 'auth_provider.dart';
import 'swipe_provider.dart';
import 'tmdb_provider.dart';

/// Maximale Anzahl TMDB-Seiten, die in einem einzigen Auffüll-Vorgang
/// nachgeladen werden - verhindert eine unkontrollierte Schleife, falls
/// TMDB über viele Seiten hinweg nur bereits bewertete Filme liefert.
const _maxPagesPerFill = 5;
const _targetQueueSize = 10;

/// Hält die Warteschlange noch unbewerteter Filme für eine Gruppen-Swipe-
/// Session. Lädt TMDB-Discover-Seiten nach, sobald die Warteschlange knapp
/// wird, und blendet Filme aus, die der aktuelle User in dieser Gruppe
/// bereits bewertet hat.
class SwipeQueueController extends AsyncNotifier<List<Movie>> {
  SwipeQueueController(this.groupId);

  final String groupId;

  final Set<int> _excludedIds = {};
  int _tmdbPage = 0;
  bool _hasMoreTmdbPages = true;

  @override
  Future<List<Movie>> build() async {
    _excludedIds.clear();
    _tmdbPage = 0;
    _hasMoreTmdbPages = true;

    final uid = _requireUid();
    final swipedIds = await ref.read(swipeRepositoryProvider).getSwipedMovieIds(
          groupId: groupId,
          uid: uid,
        );
    _excludedIds.addAll(swipedIds);

    return _fillQueue(const []);
  }

  /// Entfernt den aktuell angezeigten (gerade bewerteten) Film aus der
  /// Warteschlange und füllt bei Bedarf nach.
  Future<void> advancePastCurrent(int movieId) async {
    final current = state.value;
    if (current == null || current.isEmpty || current.first.tmdbId != movieId) return;

    final remaining = current.sublist(1);
    if (remaining.length >= 3 || !_hasMoreTmdbPages) {
      state = AsyncData(remaining);
      return;
    }

    state = const AsyncLoading<List<Movie>>();
    state = await AsyncValue.guard(() => _fillQueue(remaining));
  }

  Future<void> retry() async {
    state = const AsyncLoading<List<Movie>>();
    state = await AsyncValue.guard(() => _fillQueue(state.value ?? const []));
  }

  Future<List<Movie>> _fillQueue(List<Movie> current) async {
    var queue = current;
    var attempts = 0;

    while (queue.length < _targetQueueSize && _hasMoreTmdbPages && attempts < _maxPagesPerFill) {
      attempts++;
      final page = await ref.read(movieRepositoryProvider).discoverMovies(page: _tmdbPage + 1);
      _tmdbPage = page.page;
      _hasMoreTmdbPages = page.hasNextPage;

      final freshMovies = <Movie>[];
      for (final movie in page.movies) {
        if (_excludedIds.add(movie.tmdbId)) {
          freshMovies.add(movie);
        }
      }
      queue = [...queue, ...freshMovies];
    }

    return queue;
  }

  String _requireUid() {
    final uid = ref.read(authStateChangesProvider).value?.uid;
    if (uid == null) {
      throw StateError('SwipeQueueController benötigt einen eingeloggten User.');
    }
    return uid;
  }
}

final swipeQueueControllerProvider =
    AsyncNotifierProvider.family<SwipeQueueController, List<Movie>, String>(
  SwipeQueueController.new,
);
