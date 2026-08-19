import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_provider.dart';
import 'swipe_provider.dart';
import 'swipe_queue_controller.dart';

/// Speichert Like/Dislike für den aktuell angezeigten Film. Verhindert per
/// [AsyncValue.isLoading] mehrfaches Auslösen durch schnelles Antippen/
/// mehrfaches Swipen, während ein Speichervorgang noch läuft.
class SwipeActionController extends AsyncNotifier<void> {
  SwipeActionController(this.groupId);

  final String groupId;

  @override
  Future<void> build() async {}

  Future<void> like(int movieId) => _swipe(movieId, like: true);

  Future<void> dislike(int movieId) => _swipe(movieId, like: false);

  Future<void> _swipe(int movieId, {required bool like}) async {
    final uid = ref.read(authStateChangesProvider).value?.uid;
    if (uid == null || state.isLoading) return;

    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final service = ref.read(swipeServiceProvider);
      if (like) {
        await service.likeMovie(groupId: groupId, uid: uid, movieId: movieId);
      } else {
        await service.dislikeMovie(groupId: groupId, uid: uid, movieId: movieId);
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
