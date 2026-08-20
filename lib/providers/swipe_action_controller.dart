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

  Future<void> like(int movieId) => _swipe(movieId, decision: SwipeDecision.like);

  Future<void> dislike(int movieId) => _swipe(movieId, decision: SwipeDecision.dislike);

  /// Blendet den Film nur für den aktuellen User aus der Warteschlange
  /// dieser Gruppe aus - andere Mitglieder sehen und bewerten ihn
  /// unverändert weiter, und es entsteht dadurch nie ein Match.
  Future<void> skip(int movieId) => _swipe(movieId, decision: SwipeDecision.skip);

  /// Setzt den Film persönlich auf "Vielleicht später" (Watchlist) - wie
  /// [skip] rein persönlich, kein Einfluss auf andere Mitglieder oder die
  /// Match-Erkennung.
  Future<void> watchlist(int movieId) => _swipe(movieId, decision: SwipeDecision.watchlist);

  Future<void> _swipe(int movieId, {required SwipeDecision decision}) async {
    final uid = ref.read(authStateChangesProvider).value?.uid;
    if (uid == null || state.isLoading) return;

    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final service = ref.read(swipeServiceProvider);
      switch (decision) {
        case SwipeDecision.like:
          await service.likeMovie(groupId: groupId, uid: uid, movieId: movieId);
        case SwipeDecision.dislike:
          await service.dislikeMovie(groupId: groupId, uid: uid, movieId: movieId);
        case SwipeDecision.skip:
          await service.skipMovie(groupId: groupId, uid: uid, movieId: movieId);
        case SwipeDecision.watchlist:
          await service.watchlistMovie(groupId: groupId, uid: uid, movieId: movieId);
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
