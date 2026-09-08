import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/movie_poll.dart';
import '../models/movie_poll_option.dart';
import '../models/movie_poll_vote.dart';
import '../repositories/movie_poll_repository.dart';
import '../services/movie_poll_service.dart';
import 'auth_provider.dart';
import 'group_provider.dart';
import 'match_provider.dart';

final moviePollRepositoryProvider = Provider<MoviePollRepository>((ref) {
  return MoviePollRepository(ref.watch(firestoreProvider));
});

final moviePollServiceProvider = Provider<MoviePollService>((ref) {
  return MoviePollService(
    ref.watch(moviePollRepositoryProvider),
    ref.watch(groupRepositoryProvider),
    ref.watch(matchRepositoryProvider),
  );
});

/// Alle Filmabend-Abstimmungen einer Gruppe (§21), live, nächste Deadline
/// zuerst.
final groupMoviePollsProvider = StreamProvider.family<List<MoviePoll>, String>((
  ref,
  groupId,
) {
  return ref.watch(moviePollRepositoryProvider).watchPolls(groupId);
});

typedef MoviePollKey = ({String groupId, String pollId});

final moviePollProvider = StreamProvider.family<MoviePoll?, MoviePollKey>((ref, key) {
  return ref.watch(moviePollRepositoryProvider).watchPoll(key.groupId, key.pollId);
});

/// Terminvorschläge einer Abstimmung, live, chronologisch aufsteigend.
final moviePollOptionsProvider = StreamProvider.family<List<MoviePollOption>, MoviePollKey>((
  ref,
  key,
) {
  return ref.watch(moviePollRepositoryProvider).watchOptions(key.groupId, key.pollId);
});

/// Alle Stimmen einer Abstimmung, live - Grundlage für die Stimmenzahl pro
/// Option und die eigene aktuelle Auswahl.
final moviePollVotesProvider = StreamProvider.family<List<MoviePollVote>, MoviePollKey>((
  ref,
  key,
) {
  return ref.watch(moviePollRepositoryProvider).watchVotes(key.groupId, key.pollId);
});
