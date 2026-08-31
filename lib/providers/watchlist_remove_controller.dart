import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_provider.dart';
import 'swipe_provider.dart';

/// Entfernt einen Film aus der eigenen persönlichen Watchlist einer Gruppe.
/// Hält zusätzlich fest, *welcher* Film gerade entfernt wird ([removingMovieId])
/// - mehrere Watchlist-Karten sind gleichzeitig sichtbar, daher darf der
/// Ladezustand nicht global für alle Karten gelten, sondern nur für die
/// tatsächlich angetippte. Verhindert per [AsyncValue.isLoading] zusätzlich
/// ein mehrfaches Auslösen für denselben Film durch schnelles Antippen -
/// analog zu `SwipeActionController`.
class WatchlistRemoveController extends AsyncNotifier<void> {
  WatchlistRemoveController(this.groupId);

  final String groupId;

  int? _removingMovieId;
  int? get removingMovieId => _removingMovieId;

  @override
  Future<void> build() async {}

  Future<void> remove(int movieId) async {
    final uid = ref.read(authStateChangesProvider).value?.uid;
    if (uid == null || state.isLoading) return;

    _removingMovieId = movieId;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() {
      return ref
          .read(swipeServiceProvider)
          .removeFromWatchlist(groupId: groupId, uid: uid, movieId: movieId);
    });
    _removingMovieId = null;
  }
}

final watchlistRemoveControllerProvider =
    AsyncNotifierProvider.family<WatchlistRemoveController, void, String>(
  WatchlistRemoveController.new,
);
