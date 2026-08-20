import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../components/chat/message_bubble.dart';
import '../../models/chat_message.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_history_controller.dart';
import '../../providers/chat_provider.dart';
import '../../providers/chat_send_controller.dart';
import '../../providers/group_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/chat_error_translator.dart';

/// Echter Gruppenchat: Nachrichten in Echtzeit über Firestore, älteste
/// zuerst. Nur Gruppenmitglieder gelangen hierher (Navigation ausschließlich
/// aus `GroupDetailScreen`/der Chat-Übersicht); Firestore Security Rules
/// erzwingen die Mitgliedschaft zusätzlich unabhängig von der UI.
class GroupChatScreen extends ConsumerStatefulWidget {
  const GroupChatScreen({super.key, required this.groupId});

  final String groupId;

  @override
  ConsumerState<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends ConsumerState<GroupChatScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _send() {
    final text = _textController.text;
    if (text.trim().isEmpty) return;
    ref.read(chatSendControllerProvider(widget.groupId).notifier).send(text);
    _textController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final liveAsync = ref.watch(chatMessagesProvider(widget.groupId));
    final olderAsync = ref.watch(chatHistoryControllerProvider(widget.groupId));
    final sendState = ref.watch(chatSendControllerProvider(widget.groupId));
    final myUid = ref.watch(authStateChangesProvider).value?.uid;
    final groupName = ref.watch(groupProvider(widget.groupId)).value?.name;

    ref.listen(chatSendControllerProvider(widget.groupId), (previous, next) {
      next.whenOrNull(
        error: (error, _) => ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(translateChatError(error)))),
      );
    });

    return Scaffold(
      appBar: AppBar(title: Text(groupName == null ? 'Chat' : 'Chat · $groupName')),
      body: SafeArea(
        child: liveAsync.when(
          data: (liveMessages) {
            final older = olderAsync.value ?? const <ChatMessage>[];
            final messages = [...older, ...liveMessages];

            return Column(
              children: [
                if (messages.isEmpty)
                  const Expanded(child: _EmptyChatState())
                else
                  Expanded(
                    child: ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: messages.length + 1,
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return _LoadOlderButton(
                            groupId: widget.groupId,
                            oldestKnown: messages.first.createdAt,
                            isLoading: olderAsync.isLoading,
                          );
                        }
                        final message = messages[index - 1];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: MessageBubble(message: message, isOwn: message.senderUid == myUid),
                        );
                      },
                    ),
                  ),
                _ChatInput(
                  controller: _textController,
                  isSending: sendState.isLoading,
                  onSend: _send,
                ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator(color: AppColors.accent)),
          error: (error, _) => const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Chat konnte nicht geladen werden.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadOlderButton extends ConsumerWidget {
  const _LoadOlderButton({
    required this.groupId,
    required this.oldestKnown,
    required this.isLoading,
  });

  final String groupId;
  final DateTime oldestKnown;
  final bool isLoading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
              )
            : TextButton(
                onPressed: () => ref
                    .read(chatHistoryControllerProvider(groupId).notifier)
                    .loadOlder(oldestKnown),
                child: const Text('Ältere Nachrichten laden'),
              ),
      ),
    );
  }
}

class _EmptyChatState extends StatelessWidget {
  const _EmptyChatState();

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
              'Noch keine Nachrichten.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatInput extends StatelessWidget {
  const _ChatInput({required this.controller, required this.isSending, required this.onSend});

  final TextEditingController controller;
  final bool isSending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                enabled: !isSending,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: InputDecoration(
                  hintText: 'Nachricht schreiben...',
                  filled: true,
                  fillColor: AppColors.surfaceVariant,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Material(
              color: AppColors.accent,
              shape: const CircleBorder(),
              child: InkWell(
                onTap: isSending ? null : onSend,
                customBorder: const CircleBorder(),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: isSending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.send, color: Colors.white, size: 20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
