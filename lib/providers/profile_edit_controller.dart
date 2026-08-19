import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_provider.dart';

/// Steuert das Bearbeiten des eigenen Profilnamens.
class ProfileEditController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> updateName(String name) async {
    final uid = ref.read(authStateChangesProvider).value?.uid;
    if (uid == null || state.isLoading) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(userRepositoryProvider).updateName(uid, name),
    );
  }
}

final profileEditControllerProvider =
    AsyncNotifierProvider<ProfileEditController, void>(ProfileEditController.new);
