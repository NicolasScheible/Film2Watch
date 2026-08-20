import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../components/friends/user_avatar.dart';
import '../../models/group_model.dart';
import '../../providers/group_provider.dart';
import '../../theme/app_theme.dart';
import '../groups/group_chat_screen.dart';

/// Übersicht aller Gruppen-Chats: der globale Chat-Tab zeigt die Gruppen des
/// Nutzers, da jeder Chat an eine konkrete Gruppe gebunden ist (kein
/// gruppenübergreifender Chat). Tippen öffnet den echten Chat der Gruppe.
class ChatScreen extends ConsumerWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(myGroupsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Chat')),
      body: groups.when(
        data: (groups) {
          if (groups.isEmpty) return const _EmptyChatsState();
          return ListView.separated(
            padding: const EdgeInsets.all(24),
            itemCount: groups.length,
            separatorBuilder: (context, index) => const SizedBox(height: 4),
            itemBuilder: (context, index) => _ChatListTile(group: groups[index]),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.accent)),
        error: (error, _) =>
            const Center(child: Text('Chats konnten nicht geladen werden.')),
      ),
    );
  }
}

class _EmptyChatsState extends StatelessWidget {
  const _EmptyChatsState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline, size: 56, color: AppColors.textSecondary),
            SizedBox(height: 16),
            Text(
              'Tritt einer Gruppe bei, um dort zu chatten.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatListTile extends StatelessWidget {
  const _ChatListTile({required this.group});

  final Group group;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: UserAvatar(name: group.name, profilePicture: group.photoUrl, radius: 24),
        title: Text(group.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        trailing: const Icon(Icons.chevron_right, color: AppColors.textSecondary),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => GroupChatScreen(groupId: group.id)),
        ),
      ),
    );
  }
}
