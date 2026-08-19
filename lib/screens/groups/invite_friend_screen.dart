import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../components/friends/friend_list_tile.dart';
import '../../providers/friend_provider.dart';
import '../../providers/group_action_controller.dart';
import '../../providers/group_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/group_error_translator.dart';

/// Zeigt die eigene Freundesliste zur Auswahl, wer in die Gruppe eingeladen
/// werden soll. Es können ausschließlich Freunde eingeladen werden - keine
/// manuelle UID-Eingabe.
class InviteFriendScreen extends ConsumerWidget {
  const InviteFriendScreen({super.key, required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final friendUids = ref.watch(friendUidsProvider);
    final members = ref.watch(groupMembersProvider(groupId)).value ?? const [];
    final memberUids = members.map((m) => m.uid).toSet();
    final actionState = ref.watch(groupActionControllerProvider);

    ref.listen(groupActionControllerProvider, (previous, next) {
      next.whenOrNull(
        error: (error, _) => ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(translateGroupError(error)))),
        data: (_) {
          if (previous?.isLoading ?? false) {
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('Einladung gesendet.')));
          }
        },
      );
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Freund einladen')),
      body: friendUids.when(
        data: (uids) {
          final invitableUids = uids.where((uid) => !memberUids.contains(uid)).toList();
          if (invitableUids.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Alle deine Freunde sind bereits in dieser Gruppe.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              for (final uid in invitableUids)
                _InvitableFriendTile(
                  groupId: groupId,
                  uid: uid,
                  isLoading: actionState.isLoading,
                ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.accent)),
        error: (error, _) => const Center(child: Text('Freunde konnten nicht geladen werden.')),
      ),
    );
  }
}

class _InvitableFriendTile extends ConsumerWidget {
  const _InvitableFriendTile({
    required this.groupId,
    required this.uid,
    required this.isLoading,
  });

  final String groupId;
  final String uid;
  final bool isLoading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(publicProfileProvider(uid));

    return profile.when(
      data: (profile) {
        if (profile == null) return const SizedBox.shrink();
        return FriendListTile(
          name: profile.name,
          friendCode: profile.friendCode,
          profilePicture: profile.profilePicture,
          trailing: TextButton(
            onPressed: isLoading
                ? null
                : () => ref.read(groupActionControllerProvider.notifier).inviteFriend(groupId, uid),
            child: const Text('Einladen'),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (error, _) => const SizedBox.shrink(),
    );
  }
}
