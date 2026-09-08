import '../repositories/group_repository.dart';
import '../repositories/match_repository.dart';
import '../repositories/movie_poll_repository.dart';
import '../utils/movie_poll_exceptions.dart';

/// Orchestriert das Anlegen einer Filmabend-Abstimmung und das Abstimmen
/// selbst (§21: "Filmabend-Abstimmung"). Prüft Mitgliedschaft und
/// Geschäftsregeln, bevor überhaupt geschrieben wird - die Firestore Rules
/// erzwingen dieselben Prüfungen zusätzlich serverseitig, niemals nur
/// clientseitig vertraut (insbesondere die Deadline und das Bestimmen des
/// Gewinners, siehe `functions/moviePollEngine.js`).
///
/// Berechtigungen (mit dem Produktverantwortlichen abgestimmt):
/// - Erstellen: jedes Gruppenmitglied.
/// - Abstimmen: jedes Gruppenmitglied, mehrfach vor der Deadline änderbar.
class MoviePollService {
  MoviePollService(this._pollRepository, this._groupRepository, this._matchRepository);

  final MoviePollRepository _pollRepository;
  final GroupRepository _groupRepository;
  final MatchRepository _matchRepository;

  static const _minOptionCount = 2;

  Future<String> createPoll({
    required String groupId,
    required String uid,
    required DateTime deadline,
    required List<({DateTime scheduledAt, int platformId, int? movieId})> options,
  }) async {
    final member = await _groupRepository.getMember(groupId, uid);
    if (member == null) {
      throw const MoviePollActionException('Du bist kein Mitglied dieser Gruppe.');
    }
    if (!deadline.isAfter(DateTime.now())) {
      throw const MoviePollActionException('Die Deadline muss in der Zukunft liegen.');
    }
    if (options.length < _minOptionCount) {
      throw const MoviePollActionException(
        'Eine Abstimmung braucht mindestens $_minOptionCount Terminvorschläge.',
      );
    }
    for (final option in options) {
      final movieId = option.movieId;
      if (movieId == null) continue;
      final isMatch = await _matchRepository.isMatch(groupId, movieId);
      if (!isMatch) {
        throw const MoviePollActionException('Ein Terminvorschlag enthält einen Film, der kein Match dieser Gruppe ist.');
      }
    }

    return _pollRepository.createPoll(
      groupId: groupId,
      createdBy: uid,
      deadline: deadline,
      options: options,
    );
  }

  /// Ersetzt die komplette Stimmenauswahl von [uid] durch [optionIds]
  /// (Doodle-Prinzip, mehrfach vor der Deadline änderbar - eine erneute
  /// Abstimmung ersetzt die bisherige Auswahl vollständig).
  Future<void> vote({
    required String groupId,
    required String uid,
    required String pollId,
    required Set<String> optionIds,
  }) async {
    final member = await _groupRepository.getMember(groupId, uid);
    if (member == null) {
      throw const MoviePollActionException('Du bist kein Mitglied dieser Gruppe.');
    }
    final poll = await _pollRepository.getPoll(groupId: groupId, pollId: pollId);
    if (poll == null) {
      throw const MoviePollActionException('Diese Abstimmung existiert nicht mehr.');
    }
    if (!poll.isOpen || !poll.deadline.isAfter(DateTime.now())) {
      throw const MoviePollActionException('Diese Abstimmung ist bereits beendet.');
    }

    final options = await _pollRepository.getOptions(groupId: groupId, pollId: pollId);
    final validOptionIds = options.map((option) => option.id).toSet();
    if (!validOptionIds.containsAll(optionIds)) {
      throw const MoviePollActionException('Ein ausgewählter Terminvorschlag gehört nicht zu dieser Abstimmung.');
    }

    await _pollRepository.setMyVotes(groupId: groupId, pollId: pollId, uid: uid, optionIds: optionIds);
  }
}
