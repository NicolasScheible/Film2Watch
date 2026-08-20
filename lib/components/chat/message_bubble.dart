import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/chat_message.dart';
import '../../providers/friend_provider.dart';
import '../../theme/app_theme.dart';
import '../friends/user_avatar.dart';

String _formatTime(DateTime time) {
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

/// Eine Chat-Nachricht: eigene Nachrichten rechts (ohne Avatar/Name - der
/// Absender ist ja der Betrachter selbst), fremde Nachrichten links mit
/// Avatar und Namen aus dem bestehenden öffentlichen Profil.
class MessageBubble extends ConsumerWidget {
  const MessageBubble({super.key, required this.message, required this.isOwn});

  final ChatMessage message;
  final bool isOwn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (isOwn) {
      return Align(
        alignment: Alignment.centerRight,
        child: _Bubble(
          text: message.text,
          time: message.createdAt,
          color: AppColors.accent,
          textColor: Colors.white,
        ),
      );
    }

    final profile = ref.watch(publicProfileProvider(message.senderUid)).value;
    final name = profile?.name ?? '...';

    return Align(
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          UserAvatar(name: name, profilePicture: profile?.profilePicture, radius: 14),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 2),
                child: Text(
                  name,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ),
              _Bubble(
                text: message.text,
                time: message.createdAt,
                color: AppColors.surfaceVariant,
                textColor: AppColors.textPrimary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.text,
    required this.time,
    required this.color,
    required this.textColor,
  });

  final String text;
  final DateTime time;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, style: TextStyle(color: textColor, height: 1.3)),
            const SizedBox(height: 4),
            Text(
              _formatTime(time),
              style: TextStyle(color: textColor.withValues(alpha: 0.7), fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
