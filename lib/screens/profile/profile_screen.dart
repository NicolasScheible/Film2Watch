import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../components/auth/primary_button.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';

/// Profilbereich. Zeigt die echten Firestore-Nutzerdaten (Name, E-Mail,
/// Freundescode) sowie den Logout. Freundesliste, Statistiken und
/// Einstellungen folgen in einem eigenen Entwicklungsschritt.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userDoc = ref.watch(currentUserDocProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Profil')),
      body: userDoc.when(
        data: (appUser) {
          if (appUser == null) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(appUser.name, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 4),
                Text(appUser.email, style: const TextStyle(color: AppColors.textSecondary)),
                const SizedBox(height: 16),
                _FriendCodeChip(friendCode: appUser.friendCode),
                const Spacer(),
                PrimaryButton(
                  label: 'Ausloggen',
                  onPressed: () => ref.read(authServiceProvider).signOut(),
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.accent)),
        error: (error, stackTrace) => const Center(
          child: Text('Profil konnte nicht geladen werden.'),
        ),
      ),
    );
  }
}

class _FriendCodeChip extends StatelessWidget {
  const _FriendCodeChip({required this.friendCode});

  final String friendCode;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.qr_code_2, size: 18, color: AppColors.accentSecondary),
          const SizedBox(width: 8),
          Text(
            friendCode,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}
