import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../components/auth/primary_button.dart';
import '../../components/friends/friend_list_tile.dart';
import '../../components/friends/user_avatar.dart';
import '../../providers/auth_provider.dart';
import '../../providers/friend_action_controller.dart';
import '../../providers/friend_provider.dart';
import '../../providers/notification_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/friend_error_translator.dart';
import 'add_friend_screen.dart';
import 'edit_profile_screen.dart';
import 'friend_requests_screen.dart';

/// Profilbereich. Zeigt die echten Firestore-Nutzerdaten, den Freundescode,
/// Freundesanfragen, die Freundesliste sowie den Logout.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userDoc = ref.watch(currentUserDocProvider);

    ref.listen(friendActionControllerProvider, (previous, next) {
      next.whenOrNull(
        error: (error, _) => ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(translateFriendError(error)))),
      );
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Profil')),
      body: userDoc.when(
        data: (appUser) {
          if (appUser == null) return const SizedBox.shrink();
          final incoming = ref.watch(incomingFriendRequestsProvider).value ?? const [];
          final friendUids = ref.watch(friendUidsProvider).value ?? const [];

          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Center(
                child: UserAvatar(
                  name: appUser.name,
                  profilePicture: appUser.profilePicture,
                  radius: 44,
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(appUser.name, style: Theme.of(context).textTheme.headlineSmall),
              ),
              Center(
                child: Text(appUser.email, style: const TextStyle(color: AppColors.textSecondary)),
              ),
              const SizedBox(height: 24),
              _FriendCodeCard(friendCode: appUser.friendCode),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(context)
                          .push(MaterialPageRoute(builder: (_) => const AddFriendScreen())),
                      icon: const Icon(Icons.person_add_alt_1),
                      label: const Text('Freund hinzufügen'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              _SectionHeader(
                title: 'Freunde',
                subtitle: '${friendUids.length} ${friendUids.length == 1 ? "Freund" : "Freunde"}',
              ),
              const SizedBox(height: 8),
              _SectionHeader(
                title: 'Freundesanfragen',
                subtitle: '${incoming.length} ${incoming.length == 1 ? "Anfrage" : "Anfragen"}',
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const FriendRequestsScreen())),
              ),
              const SizedBox(height: 16),
              if (friendUids.isEmpty)
                const Text('Noch keine Freunde.', style: TextStyle(color: AppColors.textSecondary))
              else
                Column(children: [for (final uid in friendUids) _FriendTile(friendUid: uid)]),
              const SizedBox(height: 32),
              OutlinedButton(
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const EditProfileScreen())),
                child: const Text('Profil bearbeiten'),
              ),
              const SizedBox(height: 12),
              PrimaryButton(
                label: 'Ausloggen',
                onPressed: () => _signOut(ref, appUser.uid),
              ),
            ],
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

/// Meldet zuerst das eigene FCM-Gerät ab (nur das eigene - nie fremde
/// Geräte), bevor tatsächlich ausgeloggt wird: nach dem Logout ist der User
/// nicht mehr authentifiziert, die Firestore Rules würden das Entfernen des
/// eigenen Device-Dokuments dann nicht mehr erlauben.
Future<void> _signOut(WidgetRef ref, String uid) async {
  await ref.read(pushServiceProvider).unregisterCurrentDevice(uid).catchError((_) {});
  await ref.read(authServiceProvider).signOut();
}

class _FriendCodeCard extends StatelessWidget {
  const _FriendCodeCard({required this.friendCode});

  final String friendCode;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.qr_code_2, size: 20, color: AppColors.accentSecondary),
              const SizedBox(width: 8),
              const Text('Dein Freundescode', style: TextStyle(color: AppColors.textSecondary)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            friendCode,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 22,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: friendCode));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Freundescode kopiert.')),
                      );
                    }
                  },
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Code kopieren'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => SharePlus.instance.share(
                    ShareParams(
                      text: 'Füg mich bei Film2Watch hinzu! Mein Freundescode: $friendCode',
                    ),
                  ),
                  icon: const Icon(Icons.ios_share, size: 18),
                  label: const Text('Teilen'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.subtitle, this.onTap});

  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  Text(subtitle, style: const TextStyle(color: AppColors.textSecondary)),
                ],
              ),
            ),
            if (onTap != null) const Icon(Icons.chevron_right, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _FriendTile extends ConsumerWidget {
  const _FriendTile({required this.friendUid});

  final String friendUid;

  Future<void> _confirmRemove(BuildContext context, WidgetRef ref, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Freund entfernen'),
        content: Text('Möchtest du $name wirklich aus deiner Freundesliste entfernen?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Abbrechen')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Entfernen', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      ref.read(friendActionControllerProvider.notifier).removeFriend(friendUid);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(publicProfileProvider(friendUid));

    return profile.when(
      data: (profile) {
        if (profile == null) return const SizedBox.shrink();
        return FriendListTile(
          name: profile.name,
          friendCode: profile.friendCode,
          profilePicture: profile.profilePicture,
          trailing: IconButton(
            icon: const Icon(Icons.person_remove_outlined, color: AppColors.textSecondary),
            onPressed: () => _confirmRemove(context, ref, profile.name),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (error, _) => const SizedBox.shrink(),
    );
  }
}
