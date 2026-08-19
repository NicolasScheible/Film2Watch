import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_provider.dart';
import 'friend_provider.dart';

/// Steuert Freundschaftsanfrage senden/annehmen/ablehnen sowie das Entfernen
/// von Freunden. Verhindert per [AsyncValue.isLoading] mehrfaches Auslösen
/// derselben Aktion.
class FriendActionController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  String? get _myUid => ref.read(authStateChangesProvider).value?.uid;

  Future<void> sendRequest(String toUid) async {
    final myUid = _myUid;
    if (myUid == null || state.isLoading) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(friendServiceProvider).sendFriendRequest(fromUid: myUid, toUid: toUid),
    );
  }

  Future<void> acceptRequest(String fromUid) async {
    final myUid = _myUid;
    if (myUid == null || state.isLoading) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(friendServiceProvider).acceptRequest(fromUid: fromUid, toUid: myUid),
    );
  }

  Future<void> declineRequest(String fromUid) async {
    final myUid = _myUid;
    if (myUid == null || state.isLoading) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(friendServiceProvider).declineRequest(fromUid: fromUid, toUid: myUid),
    );
  }

  Future<void> removeFriend(String friendUid) async {
    final myUid = _myUid;
    if (myUid == null || state.isLoading) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(friendServiceProvider).removeFriend(myUid, friendUid),
    );
  }
}

final friendActionControllerProvider =
    AsyncNotifierProvider<FriendActionController, void>(FriendActionController.new);
