import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_provider.dart';
import 'chat_provider.dart';

/// Teilt einen Film (Filmdetail-Seite) manuell in einen Gruppenchat (§11:
/// "Teilen von Filmkarten"). Familie nach `movieId`, da die Dialog-Instanz
/// pro angezeigtem Film neu aufgebaut wird; [sharingGroupId] hält fest,
/// *welche* der ggf. mehreren angezeigten Gruppen gerade geteilt wird -
/// analog zu `WatchlistRemoveController.removingMovieId`.
class MovieShareController extends AsyncNotifier<void> {
  MovieShareController(this.movieId);

  final int movieId;

  String? _sharingGroupId;
  String? get sharingGroupId => _sharingGroupId;

  @override
  Future<void> build() async {}

  Future<void> shareToGroup(String groupId) async {
    final uid = ref.read(authStateChangesProvider).value?.uid;
    if (uid == null || state.isLoading) return;

    _sharingGroupId = groupId;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() {
      return ref
          .read(chatServiceProvider)
          .shareMovie(groupId: groupId, senderUid: uid, movieId: movieId);
    });
    _sharingGroupId = null;
  }
}

final movieShareControllerProvider =
    AsyncNotifierProvider.family<MovieShareController, void, int>(
  MovieShareController.new,
);
