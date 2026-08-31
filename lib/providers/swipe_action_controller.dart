import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/movie_swipe.dart';
import 'auth_provider.dart';
import 'swipe_provider.dart';
import 'swipe_queue_controller.dart';

/// Speichert Like/Dislike/Skip/Watchlist für den aktuell angezeigten Film.
/// Verhindert per [AsyncValue.isLoading] mehrfaches Auslösen durch schnelles
/// Antippen/mehrfaches Swipen, während ein Speichervorgang noch läuft.
class SwipeActionController extends AsyncNotifier<void> {
  SwipeActionController(this.groupId);

  final String groupId;

  @override
  Future<void> build() async {}

  Future<void> like(int movieId, {List<int> genreIds = const []}) =>
      _swipe(movieId, decision: SwipeDecision.like, genreIds: genreIds);

  Future<void> dislike(int movieId, {List<int> genreIds = const []}) =>
      _swipe(movieId, decision: SwipeDecision.dislike, genreIds: genreIds);

  /// Blendet den Film nur für den aktuellen User aus der Warteschlange
  /// dieser Gruppe aus - andere Mitglieder sehen und bewerten ihn
  /// unverändert weiter, und es entsteht dadurch nie ein Match.
  Future<void> skip(int movieId, {List<int> genreIds = const []}) =>
      _swipe(movieId, decision: SwipeDecision.skip, genreIds: genreIds);

  /// Setzt den Film persönlich auf "Vielleicht später" (Watchlist) - wie
  /// [skip] rein persönlich, kein Einfluss auf andere Mitglieder oder die
  /// Match-Erkennung.
  Future<void> watchlist(int movieId, {List<int> genreIds = const []}) =>
      _swipe(movieId, decision: SwipeDecision.watchlist, genreIds: genreIds);

  /// "Super Swipe" (§6/§15, Premium-Feature) - wirft eine
  /// [GroupActionException] über den `error`-Zustand, wenn der User kein
  /// Premium hat (siehe `SwipeService.superSwipeMovie`).
  Future<void> superSwipe(int movieId, {List<int> genreIds = const []}) =>
      _swipe(movieId, decision: SwipeDecision.superSwipe, genreIds: genreIds);

  Future<void> _swipe(
    int movieId, {
    required SwipeDecision decision,
    List<int> genreIds = const [],
  }) async {
    final uid = ref.read(authStateChangesProvider).value?.uid;
    if (uid == null || state.isLoading) return;

    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final service = ref.read(swipeServiceProvider);
      switch (decision) {
        case SwipeDecision.like:
          await service.likeMovie(
            groupId: groupId,
            uid: uid,
            movieId: movieId,
            genreIds: genreIds,
          );
        case SwipeDecision.dislike:
          await service.dislikeMovie(
            groupId: groupId,
            uid: uid,
            movieId: movieId,
            genreIds: genreIds,
          );
        case SwipeDecision.skip:
          await service.skipMovie(
            groupId: groupId,
            uid: uid,
            movieId: movieId,
            genreIds: genreIds,
          );
        case SwipeDecision.watchlist:
          await service.watchlistMovie(
            groupId: groupId,
            uid: uid,
            movieId: movieId,
            genreIds: genreIds,
          );
        case SwipeDecision.superSwipe:
          await service.superSwipeMovie(
            groupId: groupId,
            uid: uid,
            movieId: movieId,
            genreIds: genreIds,
          );
      }
      await ref
          .read(swipeQueueControllerProvider(groupId).notifier)
          .advancePastCurrent(movieId);
    });
  }
}

final swipeActionControllerProvider =
    AsyncNotifierProvider.family<SwipeActionController, void, String>(
  SwipeActionController.new,
);
