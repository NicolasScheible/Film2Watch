import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../components/friends/friend_list_tile.dart';
import '../../models/friend_request.dart';
import '../../providers/friend_action_controller.dart';
import '../../providers/friend_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/friend_error_translator.dart';

/// Eingehende und ausgehende Freundschaftsanfragen.
class FriendRequestsScreen extends ConsumerWidget {
  const FriendRequestsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final incoming = ref.watch(incomingFriendRequestsProvider);
    final outgoing = ref.watch(outgoingFriendRequestsProvider);

    ref.listen(friendActionControllerProvider, (previous, next) {
      next.whenOrNull(
        error: (error, _) => ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(translateFriendError(error)))),
      );
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Freundesanfragen')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('Eingehend', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          incoming.when(
            data: (requests) => requests.isEmpty
                ? const _EmptyHint('Keine eingehenden Anfragen.')
                : Column(children: [for (final r in requests) _IncomingRequestTile(request: r)]),
            loading: () => const Center(child: CircularProgressIndicator(color: AppColors.accent)),
            error: (error, _) => Text(translateFriendError(error)),
          ),
          const SizedBox(height: 32),
          Text('Ausgehend', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          outgoing.when(
            data: (requests) => requests.isEmpty
                ? const _EmptyHint('Keine ausgehenden Anfragen.')
                : Column(children: [for (final r in requests) _OutgoingRequestTile(request: r)]),
            loading: () => const Center(child: CircularProgressIndicator(color: AppColors.accent)),
            error: (error, _) => Text(translateFriendError(error)),
          ),
        ],
      ),
    );
  }
}

class _IncomingRequestTile extends ConsumerWidget {
  const _IncomingRequestTile({required this.request});

  final FriendRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(publicProfileProvider(request.fromUid));
    final isLoading = ref.watch(friendActionControllerProvider).isLoading;

    return profile.when(
      data: (profile) {
        if (profile == null) return const SizedBox.shrink();
        return FriendListTile(
          name: profile.name,
          friendCode: profile.friendCode,
          profilePicture: profile.profilePicture,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.check_circle, color: AppColors.accentSecondary),
                onPressed: isLoading
                    ? null
                    : () => ref
                        .read(friendActionControllerProvider.notifier)
                        .acceptRequest(request.fromUid),
              ),
              IconButton(
                icon: const Icon(Icons.cancel, color: AppColors.textSecondary),
                onPressed: isLoading
                    ? null
                    : () => ref
                        .read(friendActionControllerProvider.notifier)
                        .declineRequest(request.fromUid),
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

class _OutgoingRequestTile extends ConsumerWidget {
  const _OutgoingRequestTile({required this.request});

  final FriendRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(publicProfileProvider(request.toUid));

    return profile.when(
      data: (profile) {
        if (profile == null) return const SizedBox.shrink();
        return FriendListTile(
          name: profile.name,
          friendCode: profile.friendCode,
          profilePicture: profile.profilePicture,
          trailing: const Text('Ausstehend', style: TextStyle(color: AppColors.textSecondary)),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (error, _) => const SizedBox.shrink(),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: const TextStyle(color: AppColors.textSecondary));
  }
}
