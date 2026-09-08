import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_provider.dart';
import 'movie_poll_provider.dart';

/// Erstellt Abstimmungen und gibt Stimmen ab (§21). Verhindert per
/// [AsyncValue.isLoading] mehrfaches Auslösen durch schnelles Antippen,
/// während ein Speichervorgang noch läuft - analog zu
/// `MovieNightActionController`.
class MoviePollActionController extends AsyncNotifier<void> {
  MoviePollActionController(this.groupId);

  final String groupId;

  @override
  Future<void> build() async {}

  Future<void> create({
    required DateTime deadline,
    required List<({DateTime scheduledAt, int platformId, int? movieId})> options,
  }) async {
    final uid = ref.read(authStateChangesProvider).value?.uid;
    if (uid == null || state.isLoading) return;

    state = const AsyncLoading();
    state = await AsyncValue.guard(() {
      return ref.read(moviePollServiceProvider).createPoll(
            groupId: groupId,
            uid: uid,
            deadline: deadline,
            options: options,
          );
    });
  }

  Future<void> vote({required String pollId, required Set<String> optionIds}) async {
    final uid = ref.read(authStateChangesProvider).value?.uid;
    if (uid == null || state.isLoading) return;

    state = const AsyncLoading();
    state = await AsyncValue.guard(() {
      return ref.read(moviePollServiceProvider).vote(
            groupId: groupId,
            uid: uid,
            pollId: pollId,
            optionIds: optionIds,
          );
    });
  }
}

final moviePollActionControllerProvider =
    AsyncNotifierProvider.family<MoviePollActionController, void, String>(
  MoviePollActionController.new,
);
