import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/friend_search_result.dart';
import 'auth_provider.dart';
import 'friend_provider.dart';

/// Steuert die Freundescode-Suche im „Freund hinzufügen"-Bereich.
class FriendSearchController extends AsyncNotifier<FriendSearchResult?> {
  @override
  FriendSearchResult? build() => null;

  Future<void> search(String code) async {
    final myUid = ref.read(authStateChangesProvider).value?.uid;
    if (myUid == null || state.isLoading) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(friendServiceProvider).searchByFriendCode(myUid: myUid, code: code),
    );
  }

  void reset() => state = const AsyncData(null);
}

final friendSearchControllerProvider =
    AsyncNotifierProvider<FriendSearchController, FriendSearchResult?>(
  FriendSearchController.new,
);
