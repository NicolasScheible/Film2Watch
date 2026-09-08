import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/movie_poll.dart';
import '../../providers/movie_poll_provider.dart';
import '../../theme/app_theme.dart';
import 'movie_night_card.dart';

/// Eine Filmabend-Abstimmungs-Karte (§21: "Filmabend-Abstimmung") - Deadline,
/// Anzahl der Terminvorschläge und, sobald ausgewertet, das Ergebnis. Der
/// eigentliche Auswertungszustand (`status`/`winning_option_id`) kommt
/// ausschließlich vom Server (Scheduled Cloud Function) - diese Karte zeigt
/// ihn nur an.
class MoviePollCard extends ConsumerWidget {
  const MoviePollCard({super.key, required this.groupId, required this.poll, this.onTap});

  final String groupId;
  final MoviePoll poll;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final optionsAsync = ref.watch(moviePollOptionsProvider((groupId: groupId, pollId: poll.id)));
    final optionCount = optionsAsync.value?.length;

    return Material(
      color: AppColors.surfaceVariant,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                poll.isOpen ? Icons.how_to_vote_outlined : Icons.fact_check_outlined,
                color: AppColors.accent,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      poll.isOpen
                          ? 'Abstimmung bis ${formatMovieNightSchedule(poll.deadline)}'
                          : 'Abstimmung beendet',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    if (poll.isOpen)
                      Text(
                        optionCount != null ? '$optionCount Terminvorschläge' : 'Lädt…',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                      )
                    else
                      _ResultLabel(groupId: groupId, poll: poll),
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

class _ResultLabel extends ConsumerWidget {
  const _ResultLabel({required this.groupId, required this.poll});

  final String groupId;
  final MoviePoll poll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final winningOptionId = poll.winningOptionId;
    if (winningOptionId == null) {
      return const Text(
        'Niemand hat abgestimmt.',
        style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
      );
    }
    final options = ref.watch(moviePollOptionsProvider((groupId: groupId, pollId: poll.id))).value;
    final winningOption =
        options?.where((option) => option.id == winningOptionId).firstOrNull;
    return Text(
      winningOption != null
          ? 'Gewonnen: ${formatMovieNightSchedule(winningOption.scheduledAt)}'
          : 'Ausgewertet.',
      style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
    );
  }
}
