import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/movie_poll.dart';
import '../models/movie_poll_option.dart';
import '../models/movie_poll_vote.dart';

/// Kapselt den Firestore-Zugriff auf `groups/{groupId}/movie_night_polls`
/// (§21: "Filmabend-Abstimmung") inkl. der Unter-Collections `options` und
/// `votes`. Firestore Auto-ID pro Abstimmung/Option, analog zu
/// `MovieNightRepository`.
class MoviePollRepository {
  MoviePollRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _polls(String groupId) =>
      _firestore.collection('groups').doc(groupId).collection('movie_night_polls');

  CollectionReference<Map<String, dynamic>> _options(String groupId, String pollId) =>
      _polls(groupId).doc(pollId).collection('options');

  CollectionReference<Map<String, dynamic>> _votes(String groupId, String pollId) =>
      _polls(groupId).doc(pollId).collection('votes');

  /// Alle Abstimmungen einer Gruppe, chronologisch nach Deadline aufsteigend
  /// (die nächste zuerst) - live, analog zu `watchMovieNights`.
  Stream<List<MoviePoll>> watchPolls(String groupId) {
    return _polls(groupId)
        .orderBy('deadline')
        .snapshots()
        .map((snapshot) => snapshot.docs.map(MoviePoll.fromFirestore).toList());
  }

  Stream<MoviePoll?> watchPoll(String groupId, String pollId) {
    return _polls(groupId)
        .doc(pollId)
        .snapshots()
        .map((snapshot) => snapshot.exists ? MoviePoll.fromFirestore(snapshot) : null);
  }

  Future<MoviePoll?> getPoll({required String groupId, required String pollId}) async {
    final snapshot = await _polls(groupId).doc(pollId).get();
    return snapshot.exists ? MoviePoll.fromFirestore(snapshot) : null;
  }

  Future<List<MoviePollOption>> getOptions({required String groupId, required String pollId}) async {
    final snapshot = await _options(groupId, pollId).get();
    return snapshot.docs.map(MoviePollOption.fromFirestore).toList();
  }

  /// Terminvorschläge einer Abstimmung, chronologisch nach Termin aufsteigend
  /// - dieselbe Reihenfolge, die auch der Tie-Break der Scheduled Cloud
  /// Function verwendet (frühester Termin gewinnt bei Gleichstand).
  Stream<List<MoviePollOption>> watchOptions(String groupId, String pollId) {
    return _options(groupId, pollId)
        .orderBy('scheduled_at')
        .snapshots()
        .map((snapshot) => snapshot.docs.map(MoviePollOption.fromFirestore).toList());
  }

  /// Alle Stimmen einer Abstimmung (aller Mitglieder) - Grundlage für die
  /// live angezeigte Stimmenzahl pro Option. Kleine, gruppengebundene Menge
  /// (Mitglieder × ausgewählte Optionen), daher unpaginiert.
  Stream<List<MoviePollVote>> watchVotes(String groupId, String pollId) {
    return _votes(groupId, pollId)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(MoviePollVote.fromFirestore).toList());
  }

  /// Legt die Abstimmung und alle Terminvorschläge atomar in einem Batch an -
  /// entweder entsteht die vollständige Abstimmung mit allen Optionen, oder
  /// keine von beidem.
  Future<String> createPoll({
    required String groupId,
    required String createdBy,
    required DateTime deadline,
    required List<({DateTime scheduledAt, int platformId, int? movieId})> options,
  }) async {
    final pollRef = _polls(groupId).doc();
    final batch = _firestore.batch();
    batch.set(pollRef, MoviePoll.toFirestoreCreate(createdBy: createdBy, deadline: deadline));
    for (final option in options) {
      batch.set(
        _options(groupId, pollRef.id).doc(),
        MoviePollOption.toFirestoreCreate(
          scheduledAt: option.scheduledAt,
          platformId: option.platformId,
          movieId: option.movieId,
        ),
      );
    }
    await batch.commit();
    return pollRef.id;
  }

  /// Ersetzt die komplette bisherige Stimmenauswahl von [uid] in dieser
  /// Abstimmung durch [optionIds] (Doodle-Prinzip: mehrere Optionen möglich,
  /// keine Abstimmungshistorie). Liest zunächst die eigenen, bestehenden
  /// Stimmen und schreibt anschließend nur die tatsächliche Differenz
  /// (gelöschte + neue Stimmen) in einem Batch - ein erneutes Abstimmen mit
  /// unveränderter Auswahl erzeugt keinen unnötigen Schreibvorgang.
  Future<void> setMyVotes({
    required String groupId,
    required String pollId,
    required String uid,
    required Set<String> optionIds,
  }) async {
    final existing = await _votes(groupId, pollId).where('uid', isEqualTo: uid).get();
    final existingByOptionId = {
      for (final doc in existing.docs) doc.data()['option_id'] as String?: doc.reference,
    };
    final existingOptionIds = existingByOptionId.keys.whereType<String>().toSet();

    final toRemove = existingOptionIds.difference(optionIds);
    final toAdd = optionIds.difference(existingOptionIds);
    if (toRemove.isEmpty && toAdd.isEmpty) return;

    final batch = _firestore.batch();
    for (final optionId in toRemove) {
      final ref = existingByOptionId[optionId];
      if (ref != null) batch.delete(ref);
    }
    for (final optionId in toAdd) {
      final voteId = MoviePollVote.idFor(uid: uid, optionId: optionId);
      batch.set(_votes(groupId, pollId).doc(voteId), MoviePollVote.toFirestoreCreate(uid: uid, optionId: optionId));
    }
    await batch.commit();
  }
}
