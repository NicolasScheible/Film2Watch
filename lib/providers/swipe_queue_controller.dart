import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/movie.dart';
import '../models/movie_filter.dart';
import '../models/user_genre_preferences.dart';
import '../utils/boost.dart';
import 'auth_provider.dart';
import 'friend_provider.dart';
import 'movie_filter_provider.dart';
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
  MovieFilter _filter = MovieFilter.empty;
  Map<int, int> _friendLikeCounts = const {};
  UserGenrePreferences _genrePreferences = UserGenrePreferences.empty;

  @override
  Future<List<Movie>> build() async {
    // `watch` statt `read`: jede Filteränderung löst automatisch einen
    // kompletten Neuaufbau dieser Methode aus - die Warteschlange wird nie
    // mit alten, unter dem vorherigen Filter geladenen Filmen weitergeführt.
    _filter = ref.watch(movieFilterControllerProvider(groupId));
    _excludedIds.clear();
    _tmdbPage = 0;
    _hasMoreTmdbPages = true;

    final uid = _requireUid();
    final swipedIds = await ref.read(swipeRepositoryProvider).getSwipedMovieIds(
          groupId: groupId,
          uid: uid,
        );
    _excludedIds.addAll(swipedIds);

    // Freundes-Likes-Boost (§7/§18): zählt pro Film, wie viele Freunde des
    // aktuellen Users ihn in dieser Gruppe geliked haben. Nur einmal pro
    // Session-Aufbau berechnet (wie die Filterauswahl) - kein Live-Update
    // während einer laufenden Swipe-Session, das verlangt die
    // Master-Spezifikation nicht.
    // `watch(...future)` statt `read(...future)`: verankert die Abhängigkeit
    // an der Lebensdauer dieses Controllers - ein reines `ref.read(...future)`
    // hält den `friendUidsProvider` nicht am Leben und kann während des
    // Awaits vom Container aufgeräumt werden (führt zu "was disposed during
    // loading state"-Fehlern), da nichts sonst diesen Provider abonniert.
    final friendUids = (await ref.watch(friendUidsProvider.future)).toSet();
    final groupLikes = await ref.read(swipeRepositoryProvider).getGroupLikes(groupId);
    _friendLikeCounts = countFriendLikes(groupLikes: groupLikes, friendUids: friendUids);

    // Genre-Präferenz/Anti-Boost (§7/§18): serverseitig von
    // `functions/userPreferences.js` gepflegt, hier nur gelesen - global pro
    // User (nicht pro Gruppe), analog zum Freundes-Boost nur einmal pro
    // Session-Aufbau geladen.
    _genrePreferences = await ref.read(userPreferencesRepositoryProvider).getPreferences(uid);

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
      final page = await ref
          .read(movieRepositoryProvider)
          .discoverMovies(page: _tmdbPage + 1, filter: _filter);
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

    // §7: voller personalisierter Boost-Score (Freundes-Likes, Genre-
    // Präferenz, Anti-Boost, Bewertung, Zufall) - sortiert ausschließlich
    // innerhalb der bereits gefilterten, deduplizierten, noch nicht
    // bewerteten Kandidaten. Fügt nie einen Film hinzu oder entfernt einen -
    // reine Umordnung.
    return sortByBoostScore(
      queue,
      friendLikeCounts: _friendLikeCounts,
      topGenres: _genrePreferences.topGenres,
      dislikedGenres: _genrePreferences.dislikedGenres,
    );
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
