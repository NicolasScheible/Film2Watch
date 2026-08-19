import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';
import 'app_shell.dart';
import 'auth/auth_screen.dart';
import 'auth/complete_profile_screen.dart';

/// Entscheidet auf Basis des Firebase-Auth-Zustands, ob der Auth-Bereich,
/// die Profil-Vervollständigung oder die Haupt-App angezeigt wird.
class AppGate extends ConsumerWidget {
  const AppGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateChangesProvider);

    return authState.when(
      data: (user) {
        if (user == null) return const AuthScreen();
        return const _AuthenticatedGate();
      },
      loading: () => const _SplashScreen(),
      error: (error, stackTrace) => const AuthScreen(),
    );
  }
}

class _AuthenticatedGate extends ConsumerWidget {
  const _AuthenticatedGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userDoc = ref.watch(currentUserDocProvider);

    return userDoc.when(
      data: (appUser) {
        if (appUser == null || appUser.name.trim().isEmpty) {
          return const CompleteProfileScreen();
        }
        return const AppShell();
      },
      loading: () => const _SplashScreen(),
      error: (error, stackTrace) => const _SplashScreen(),
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: CircularProgressIndicator(color: AppColors.accent),
      ),
    );
  }
}
