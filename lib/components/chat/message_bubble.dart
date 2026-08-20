import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/chat_message.dart';
import '../../providers/friend_provider.dart';
import '../../providers/tmdb_provider.dart';
import '../../screens/movies/movie_detail_screen.dart';
import '../../services/tmdb_image_service.dart';
import '../../theme/app_theme.dart';
import '../friends/user_avatar.dart';

String _formatTime(DateTime time) {
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

/// Eine Chat-Nachricht. Bei [ChatMessageType.match] eine zentrierte
/// System-Karte mit dem Film, der zum Match geführt hat (siehe
/// `functions/postMatchChatMessage.js`); ansonsten eine normale
/// Text-Nachricht - eigene rechts (ohne Avatar/Name - der Absender ist ja
/// der Betrachter selbst), fremde links mit Avatar und Namen aus dem
/// bestehenden öffentlichen Profil.
class MessageBubble extends ConsumerWidget {
  const MessageBubble({super.key, required this.message, required this.isOwn});

  final ChatMessage message;
  final bool isOwn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (message.type == ChatMessageType.match) {
      return _MatchMessageCard(movieId: message.movieId!);
    }

    if (isOwn) {
      return Align(
        alignment: Alignment.centerRight,
        child: _Bubble(
          text: message.text!,
          time: message.createdAt,
          color: AppColors.accent,
          textColor: Colors.white,
        ),
      );
    }

    final profile = ref.watch(publicProfileProvider(message.senderUid!)).value;
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
                text: message.text!,
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

/// System-Nachricht für ein neues Match: zentriert, visuell klar von
/// normalen Chat-Bubbles unterschieden, mit TMDB-Poster/Titel des
/// gematchten Films. Tippen öffnet die Filmdetails.
class _MatchMessageCard extends ConsumerWidget {
  const _MatchMessageCard({required this.movieId});

  final int movieId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final movieAsync = ref.watch(movieDetailsProvider(movieId));

    return Align(
      alignment: Alignment.center,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => MovieDetailScreen(tmdbId: movieId)),
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.accentSecondary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.accentSecondary.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 32,
                  height: 48,
                  child: movieAsync.when(
                    data: (movie) {
                      final posterUrl = TmdbImageService.posterUrl(movie.posterPath);
                      return posterUrl == null
                          ? Container(color: AppColors.surfaceVariant)
                          : Image.network(
                              posterUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  Container(color: AppColors.surfaceVariant),
                            );
                    },
                    loading: () => Container(color: AppColors.surfaceVariant),
                    error: (error, _) => Container(color: AppColors.surfaceVariant),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Neuer Match! 🍿',
                      style: TextStyle(
                        color: AppColors.accentSecondary,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                    movieAsync.when(
                      data: (movie) => Text(
                        movie.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                      ),
                      loading: () => const SizedBox.shrink(),
                      error: (error, _) => const Text(
                        'Film konnte nicht geladen werden.',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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
