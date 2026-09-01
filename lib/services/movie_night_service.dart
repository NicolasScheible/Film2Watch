import '../models/movie_night.dart';
import '../repositories/group_repository.dart';
import '../repositories/match_repository.dart';
import '../repositories/movie_night_repository.dart';
import '../utils/movie_night_exceptions.dart';

/// Orchestriert das Anlegen/Bearbeiten/Absagen von Filmabenden (§12: "Filmabend
/// planen"). Prüft Mitgliedschaft und Berechtigung, bevor überhaupt
/// geschrieben wird (die Firestore Rules erzwingen dieselben Prüfungen
/// zusätzlich serverseitig, niemals nur clientseitig vertraut).
///
/// Berechtigungen (mit dem Produktverantwortlichen abgestimmt):
/// - Erstellen: jedes Gruppenmitglied.
/// - Bearbeiten/Absagen: der Ersteller selbst oder der Gruppen-Admin.
class MovieNightService {
  MovieNightService(this._movieNightRepository, this._groupRepository, this._matchRepository);

  final MovieNightRepository _movieNightRepository;
  final GroupRepository _groupRepository;
  final MatchRepository _matchRepository;

  Future<void> createMovieNight({
    required String groupId,
    required String uid,
    required DateTime scheduledAt,
    required int platformId,
    int? movieId,
  }) async {
    final member = await _groupRepository.getMember(groupId, uid);
    if (member == null) {
      throw const MovieNightActionException('Du bist kein Mitglied dieser Gruppe.');
    }
    await _requireExistingMatchIfSet(groupId, movieId);

    await _movieNightRepository.createMovieNight(
      groupId: groupId,
      createdBy: uid,
      scheduledAt: scheduledAt,
      platformId: platformId,
      movieId: movieId,
    );
  }

  Future<void> updateMovieNight({
    required String groupId,
    required String uid,
    required String movieNightId,
    required DateTime scheduledAt,
    required int platformId,
    int? movieId,
  }) async {
    final movieNight = await _requireManageable(groupId: groupId, uid: uid, movieNightId: movieNightId);
    await _requireExistingMatchIfSet(groupId, movieId);

    await _movieNightRepository.updateMovieNight(
      groupId: groupId,
      movieNightId: movieNight.id,
      scheduledAt: scheduledAt,
      platformId: platformId,
      movieId: movieId,
    );
  }

  /// Absagen/Löschen (§12: austauschbare Begriffe für dieselbe Aktion).
  Future<void> cancelMovieNight({
    required String groupId,
    required String uid,
    required String movieNightId,
  }) async {
    final movieNight = await _requireManageable(groupId: groupId, uid: uid, movieNightId: movieNightId);
    await _movieNightRepository.cancelMovieNight(groupId: groupId, movieNightId: movieNight.id);
  }

  Future<void> _requireExistingMatchIfSet(String groupId, int? movieId) async {
    if (movieId == null) return;
    final isMatch = await _matchRepository.isMatch(groupId, movieId);
    if (!isMatch) {
      throw const MovieNightActionException(
        'Dieser Film ist kein Match dieser Gruppe.',
      );
    }
  }

  Future<MovieNight> _requireManageable({
    required String groupId,
    required String uid,
    required String movieNightId,
  }) async {
    final member = await _groupRepository.getMember(groupId, uid);
    if (member == null) {
      throw const MovieNightActionException('Du bist kein Mitglied dieser Gruppe.');
    }
    final movieNight = await _movieNightRepository.getMovieNight(
      groupId: groupId,
      movieNightId: movieNightId,
    );
    if (movieNight == null) {
      throw const MovieNightActionException('Dieser Filmabend existiert nicht mehr.');
    }
    if (movieNight.createdBy != uid && !member.isAdmin) {
      throw const MovieNightActionException(
        'Nur der Ersteller oder ein Admin darf diesen Filmabend bearbeiten oder absagen.',
      );
    }
    return movieNight;
  }
}
