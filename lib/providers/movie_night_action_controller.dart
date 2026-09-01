import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_provider.dart';
import 'movie_night_provider.dart';

/// Erstellt/bearbeitet/sagt Filmabende ab (§12). Verhindert per
/// [AsyncValue.isLoading] mehrfaches Auslösen durch schnelles Antippen,
/// während ein Speichervorgang noch läuft - analog zu
/// `SwipeActionController`/`ChatSendController`.
class MovieNightActionController extends AsyncNotifier<void> {
  MovieNightActionController(this.groupId);

  final String groupId;

  @override
  Future<void> build() async {}

  Future<void> create({
    required DateTime scheduledAt,
    required int platformId,
    int? movieId,
  }) async {
    final uid = ref.read(authStateChangesProvider).value?.uid;
    if (uid == null || state.isLoading) return;

    state = const AsyncLoading();
    state = await AsyncValue.guard(() {
      return ref.read(movieNightServiceProvider).createMovieNight(
            groupId: groupId,
            uid: uid,
            scheduledAt: scheduledAt,
            platformId: platformId,
            movieId: movieId,
          );
    });
  }

  Future<void> edit({
    required String movieNightId,
    required DateTime scheduledAt,
    required int platformId,
    int? movieId,
  }) async {
    final uid = ref.read(authStateChangesProvider).value?.uid;
    if (uid == null || state.isLoading) return;

    state = const AsyncLoading();
    state = await AsyncValue.guard(() {
      return ref.read(movieNightServiceProvider).updateMovieNight(
            groupId: groupId,
            uid: uid,
            movieNightId: movieNightId,
            scheduledAt: scheduledAt,
            platformId: platformId,
            movieId: movieId,
          );
    });
  }

  Future<void> cancel(String movieNightId) async {
    final uid = ref.read(authStateChangesProvider).value?.uid;
    if (uid == null || state.isLoading) return;

    state = const AsyncLoading();
    state = await AsyncValue.guard(() {
      return ref.read(movieNightServiceProvider).cancelMovieNight(
            groupId: groupId,
            uid: uid,
            movieNightId: movieNightId,
          );
    });
  }
}

final movieNightActionControllerProvider =
    AsyncNotifierProvider.family<MovieNightActionController, void, String>(
  MovieNightActionController.new,
);
