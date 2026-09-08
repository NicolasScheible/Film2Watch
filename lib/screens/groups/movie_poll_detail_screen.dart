import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../components/movies/movie_night_card.dart';
import '../../models/movie_poll_option.dart';
import '../../providers/auth_provider.dart';
import '../../providers/movie_poll_action_controller.dart';
import '../../providers/movie_poll_provider.dart';
import '../../providers/tmdb_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/movie_poll_error_translator.dart';

/// Zeigt die Terminvorschläge einer Filmabend-Abstimmung (§21) mit ihrer
/// jeweiligen Stimmenzahl an und erlaubt Mitgliedern, mehrere passende
/// Optionen auszuwählen (Doodle-Prinzip). Jedes Antippen sendet die
/// vollständige, aktuelle Auswahl sofort an den Server - kein separater
/// "Abstimmen"-Button, keine lokale Zwischenauswahl, die von der echten,
/// live einsehbaren Stimme abweichen könnte. Nach der Deadline (serverseitig
/// über `firestore.rules` erzwungen) zeigt der Screen nur noch das
/// Ergebnis an.
class MoviePollDetailScreen extends ConsumerWidget {
  const MoviePollDetailScreen({super.key, required this.groupId, required this.pollId});

  final String groupId;
  final String pollId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (groupId: groupId, pollId: pollId);
    final pollAsync = ref.watch(moviePollProvider(key));
    final optionsAsync = ref.watch(moviePollOptionsProvider(key));
    final votesAsync = ref.watch(moviePollVotesProvider(key));
    final myUid = ref.watch(authStateChangesProvider).value?.uid;
    final actionState = ref.watch(moviePollActionControllerProvider(groupId));

    ref.listen(moviePollActionControllerProvider(groupId), (previous, next) {
      next.whenOrNull(
        error: (error, _) => ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(translateMoviePollError(error)))),
      );
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Abstimmung')),
      body: SafeArea(
        child: pollAsync.when(
          data: (poll) {
            if (poll == null) {
              return const Center(child: Text('Diese Abstimmung existiert nicht mehr.'));
            }
            final canVote = poll.isOpen && poll.deadline.isAfter(DateTime.now());
            return optionsAsync.when(
              data: (options) => votesAsync.when(
                data: (votes) {
                  final myVoteOptionIds = votes
                      .where((vote) => vote.uid == myUid)
                      .map((vote) => vote.optionId)
                      .toSet();
                  final voteCountByOptionId = <String, int>{};
                  for (final vote in votes) {
                    voteCountByOptionId[vote.optionId] = (voteCountByOptionId[vote.optionId] ?? 0) + 1;
                  }

                  return ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      Text(
                        poll.isOpen
                            ? 'Abstimmung läuft bis ${formatMovieNightSchedule(poll.deadline)}.'
                            : 'Die Abstimmung ist beendet.',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (!poll.isOpen) ...[
                        const SizedBox(height: 8),
                        Text(
                          poll.winningOptionId != null
                              ? 'Ergebnis: die Mehrheit hat sich entschieden - der Filmabend wurde geplant.'
                              : 'Niemand hat abgestimmt - es gibt kein Ergebnis.',
                          style: const TextStyle(color: AppColors.textSecondary),
                        ),
                      ] else if (myUid == null) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'Mehrfachauswahl möglich - tippe alle Termine an, die dir passen.',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ],
                      const SizedBox(height: 20),
                      for (final option in options) ...[
                        _OptionVoteTile(
                          groupId: groupId,
                          option: option,
                          voteCount: voteCountByOptionId[option.id] ?? 0,
                          isSelected: myVoteOptionIds.contains(option.id),
                          isWinner: poll.winningOptionId == option.id,
                          enabled: canVote && myUid != null && !actionState.isLoading,
                          onToggle: () {
                            final next = Set<String>.from(myVoteOptionIds);
                            if (next.contains(option.id)) {
                              next.remove(option.id);
                            } else {
                              next.add(option.id);
                            }
                            ref
                                .read(moviePollActionControllerProvider(groupId).notifier)
                                .vote(pollId: pollId, optionIds: next);
                          },
                        ),
                        const SizedBox(height: 12),
                      ],
                    ],
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator(color: AppColors.accent)),
                error: (error, _) =>
                    const Center(child: Text('Stimmen konnten nicht geladen werden.')),
              ),
              loading: () => const Center(child: CircularProgressIndicator(color: AppColors.accent)),
              error: (error, _) =>
                  const Center(child: Text('Terminvorschläge konnten nicht geladen werden.')),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator(color: AppColors.accent)),
          error: (error, _) => const Center(child: Text('Abstimmung konnte nicht geladen werden.')),
        ),
      ),
    );
  }
}

class _OptionVoteTile extends ConsumerWidget {
  const _OptionVoteTile({
    required this.groupId,
    required this.option,
    required this.voteCount,
    required this.isSelected,
    required this.isWinner,
    required this.enabled,
    required this.onToggle,
  });

  final String groupId;
  final MoviePollOption option;
  final int voteCount;
  final bool isSelected;
  final bool isWinner;
  final bool enabled;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final providers = ref.watch(watchProviderListProvider).value ?? const [];
    final matchingPlatforms = providers.where((p) => p.providerId == option.platformId);
    final platformName = matchingPlatforms.isEmpty ? 'Plattform' : matchingPlatforms.first.providerName;

    return Material(
      color: isWinner ? AppColors.accent.withValues(alpha: 0.15) : AppColors.surfaceVariant,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: enabled ? onToggle : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                color: isSelected ? AppColors.accent : AppColors.textSecondary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text(
                          formatMovieNightSchedule(option.scheduledAt),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        if (isWinner) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.emoji_events, size: 16, color: AppColors.accent),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      platformName,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                    ),
                  ],
                ),
              ),
              Text(
                voteCount == 1 ? '1 Stimme' : '$voteCount Stimmen',
                style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
