import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../components/friends/user_avatar.dart';
import '../../models/group_invitation.dart';
import '../../providers/friend_provider.dart';
import '../../providers/group_action_controller.dart';
import '../../providers/group_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/group_error_translator.dart';

/// Eingehende Gruppeneinladungen.
class GroupInvitationsScreen extends ConsumerWidget {
  const GroupInvitationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invitations = ref.watch(incomingGroupInvitationsProvider);

    ref.listen(groupActionControllerProvider, (previous, next) {
      next.whenOrNull(
        error: (error, _) => ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(translateGroupError(error)))),
      );
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Gruppeneinladungen')),
      body: invitations.when(
        data: (invitations) {
          if (invitations.isEmpty) {
            return const Center(
              child: Text(
                'Keine offenen Gruppeneinladungen.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [for (final invitation in invitations) _InvitationTile(invitation: invitation)],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.accent)),
        error: (error, _) => const Center(child: Text('Einladungen konnten nicht geladen werden.')),
      ),
    );
  }
}

class _InvitationTile extends ConsumerWidget {
  const _InvitationTile({required this.invitation});

  final GroupInvitation invitation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final group = ref.watch(groupProvider(invitation.groupId));
    final inviter = ref.watch(publicProfileProvider(invitation.inviterUid));
    final isLoading = ref.watch(groupActionControllerProvider).isLoading;

    return group.when(
      data: (group) {
        if (group == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              UserAvatar(name: group.name, profilePicture: group.photoUrl, radius: 22),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      group.name,
                      style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      'von ${inviter.value?.name ?? '...'}',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.check_circle, color: AppColors.accentSecondary),
                onPressed: isLoading
                    ? null
                    : () => ref
                        .read(groupActionControllerProvider.notifier)
                        .acceptInvitation(invitation.groupId),
              ),
              IconButton(
                icon: const Icon(Icons.cancel, color: AppColors.textSecondary),
                onPressed: isLoading
                    ? null
                    : () => ref
                        .read(groupActionControllerProvider.notifier)
                        .declineInvitation(invitation.groupId),
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (error, _) => const SizedBox.shrink(),
    );
  }
}
