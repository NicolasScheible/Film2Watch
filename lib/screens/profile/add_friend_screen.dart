import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../components/auth/auth_text_field.dart';
import '../../components/auth/primary_button.dart';
import '../../components/friends/friend_list_tile.dart';
import '../../models/friend_search_result.dart';
import '../../providers/friend_action_controller.dart';
import '../../providers/friend_search_controller.dart';
import '../../theme/app_theme.dart';
import '../../utils/friend_error_translator.dart';

/// Freundescode eingeben, den zugehörigen User finden und eine
/// Freundschaftsanfrage senden.
class AddFriendScreen extends ConsumerStatefulWidget {
  const AddFriendScreen({super.key});

  @override
  ConsumerState<AddFriendScreen> createState() => _AddFriendScreenState();
}

class _AddFriendScreenState extends ConsumerState<AddFriendScreen> {
  final _codeController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _search() {
    final code = _codeController.text.trim();
    if (code.isEmpty) return;
    ref.read(friendSearchControllerProvider.notifier).search(code);
  }

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(friendSearchControllerProvider);
    final actionState = ref.watch(friendActionControllerProvider);

    ref.listen(friendActionControllerProvider, (previous, next) {
      next.whenOrNull(
        error: (error, _) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(translateFriendError(error))));
        },
        data: (_) {
          if (previous?.isLoading ?? false) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Freundschaftsanfrage gesendet.')),
            );
            ref.read(friendSearchControllerProvider.notifier).reset();
            _codeController.clear();
          }
        },
      );
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Freund hinzufügen')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Gib den Freundescode deiner Freundin/deines Freundes ein.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            AuthTextField(
              label: 'Freundescode (z. B. FILM-4821)',
              controller: _codeController,
              textInputAction: TextInputAction.search,
            ),
            const SizedBox(height: 16),
            PrimaryButton(
              label: 'Suchen',
              isLoading: searchState.isLoading,
              onPressed: _search,
            ),
            const SizedBox(height: 24),
            searchState.when(
              data: (result) => _SearchResultView(
                result: result,
                isSending: actionState.isLoading,
                onSendRequest: (uid) =>
                    ref.read(friendActionControllerProvider.notifier).sendRequest(uid),
              ),
              loading: () => const SizedBox.shrink(),
              error: (error, _) => Text(
                translateFriendError(error),
                style: const TextStyle(color: Colors.redAccent),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchResultView extends StatelessWidget {
  const _SearchResultView({
    required this.result,
    required this.isSending,
    required this.onSendRequest,
  });

  final FriendSearchResult? result;
  final bool isSending;
  final void Function(String uid) onSendRequest;

  @override
  Widget build(BuildContext context) {
    final current = result;
    if (current == null) return const SizedBox.shrink();

    return switch (current) {
      FriendSearchNotFound() => const _StatusMessage('Kein Nutzer mit diesem Freundescode gefunden.'),
      FriendSearchOwnCode() => const _StatusMessage('Das ist dein eigener Freundescode.'),
      FriendSearchAlreadyFriends(profile: final profile) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FriendListTile(name: profile.name, friendCode: profile.friendCode, profilePicture: profile.profilePicture),
            const _StatusMessage('Ihr seid bereits befreundet.'),
          ],
        ),
      FriendSearchRequestAlreadySent(profile: final profile) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FriendListTile(name: profile.name, friendCode: profile.friendCode, profilePicture: profile.profilePicture),
            const _StatusMessage('Anfrage bereits gesendet.'),
          ],
        ),
      FriendSearchIncomingRequestExists(profile: final profile) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FriendListTile(name: profile.name, friendCode: profile.friendCode, profilePicture: profile.profilePicture),
            const _StatusMessage('Dieser Nutzer hat dir bereits eine Anfrage gesendet. Schau in deinen Freundesanfragen vorbei.'),
          ],
        ),
      FriendSearchFound(profile: final profile) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FriendListTile(name: profile.name, friendCode: profile.friendCode, profilePicture: profile.profilePicture),
            const SizedBox(height: 16),
            PrimaryButton(
              label: 'Freundschaftsanfrage senden',
              isLoading: isSending,
              onPressed: () => onSendRequest(profile.uid),
            ),
          ],
        ),
    };
  }
}

class _StatusMessage extends StatelessWidget {
  const _StatusMessage(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(message, style: const TextStyle(color: AppColors.textSecondary)),
    );
  }
}
