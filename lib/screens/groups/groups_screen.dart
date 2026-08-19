import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../components/friends/user_avatar.dart';
import '../../models/group_model.dart';
import '../../providers/group_provider.dart';
import '../../theme/app_theme.dart';
import 'create_group_screen.dart';
import 'group_detail_screen.dart';
import 'group_invitations_screen.dart';

/// Übersicht der Gruppen eines Nutzers.
class GroupsScreen extends ConsumerWidget {
  const GroupsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(myGroupsProvider);
    final invitationCount = ref.watch(incomingGroupInvitationsProvider).value?.length ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gruppen'),
        actions: [
          IconButton(
            tooltip: 'Gruppeneinladungen',
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const GroupInvitationsScreen())),
            icon: Badge(
              label: Text('$invitationCount'),
              isLabelVisible: invitationCount > 0,
              child: const Icon(Icons.mail_outline),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const CreateGroupScreen())),
        icon: const Icon(Icons.add),
        label: const Text('Gruppe erstellen'),
      ),
      body: groups.when(
        data: (groups) {
          if (groups.isEmpty) return const _EmptyGroupsState();
          return ListView.separated(
            padding: const EdgeInsets.all(24),
            itemCount: groups.length,
            separatorBuilder: (context, index) => const SizedBox(height: 4),
            itemBuilder: (context, index) => _GroupTile(group: groups[index]),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.accent)),
        error: (error, stackTrace) =>
            const Center(child: Text('Gruppen konnten nicht geladen werden.')),
      ),
    );
  }
}

class _EmptyGroupsState extends StatelessWidget {
  const _EmptyGroupsState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.groups_outlined, size: 56, color: AppColors.textSecondary),
            const SizedBox(height: 16),
            const Text(
              'Du bist noch in keiner Gruppe.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 15),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const CreateGroupScreen())),
              style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
              icon: const Icon(Icons.add),
              label: const Text('Gruppe erstellen'),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupTile extends ConsumerWidget {
  const _GroupTile({required this.group});

  final Group group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memberCountAsync = ref.watch(groupMembersProvider(group.id));
    final memberCount = memberCountAsync.value?.length;

    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: UserAvatar(name: group.name, profilePicture: group.photoUrl, radius: 24),
        title: Text(group.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          memberCount == null
              ? ' '
              : '$memberCount ${memberCount == 1 ? "Mitglied" : "Mitglieder"}',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        trailing: const Icon(Icons.chevron_right, color: AppColors.textSecondary),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => GroupDetailScreen(groupId: group.id)),
        ),
      ),
    );
  }
}
