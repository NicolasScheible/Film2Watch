import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_provider.dart';

/// Steuert Loading-/Error-/Success-Zustand für Login-, Registrierungs- und
/// Social-Sign-In-Aktionen. Verhindert per [AsyncValue.isLoading]
/// mehrfaches Absenden während eine Aktion läuft.
class AuthFormController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    if (state.isLoading) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(authServiceProvider).signInWithEmail(
            email: email,
            password: password,
          ),
    );
  }

  Future<void> registerWithEmail({
    required String name,
    required String email,
    required String password,
  }) async {
    if (state.isLoading) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(authServiceProvider).registerWithEmail(
            name: name,
            email: email,
            password: password,
          ),
    );
  }

  Future<void> sendPasswordResetEmail(String email) async {
    if (state.isLoading) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(authServiceProvider).sendPasswordResetEmail(email),
    );
  }

  Future<void> signInWithGoogle() async {
    if (state.isLoading) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(authServiceProvider).signInWithGoogle(),
    );
  }

  Future<void> signInWithApple() async {
    if (state.isLoading) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(authServiceProvider).signInWithApple(),
    );
  }
}

final authFormControllerProvider =
    AsyncNotifierProvider<AuthFormController, void>(AuthFormController.new);
