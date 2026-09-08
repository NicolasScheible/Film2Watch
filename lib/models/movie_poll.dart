import 'package:cloud_firestore/cloud_firestore.dart';

/// Eine Filmabend-Abstimmung (§21 der Master-Spezifikation: "Filmabend-
/// Abstimmung" - mehrere Terminvorschläge, Mitglieder stimmen ab, Auswertung
/// nach einer Deadline). Ergänzt die einfache §12-Terminplanung
/// (`MovieNight`) um den dort bewusst zurückgestellten Abstimmungsfall -
/// beide Features bleiben getrennt, siehe `MovieNight`-Doc-Kommentar.
///
/// `groups/{groupId}/movie_night_polls/{pollId}`, Firestore Auto-ID (eine
/// Gruppe kann mehrere Abstimmungen gleichzeitig haben, analog zu
/// `movie_nights`). Die Terminvorschläge liegen in der Unter-Collection
/// `options`, die Stimmen in `votes` (siehe `MoviePollOption`/`MoviePollVote`).
///
/// `status`/`winningOptionId`/`resultMovieNightId`/`resolvedAt` werden
/// ausschließlich serverseitig von der Scheduled Cloud Function
/// `functions/moviePollEngine.js` gesetzt (Admin-SDK, umgeht Rules) - kein
/// Client, auch nicht der Ersteller, darf den Gewinner selbst bestimmen oder
/// die Abstimmung vorzeitig schließen (`firestore.rules`: `allow update: if
/// false`).
class MoviePoll {
  const MoviePoll({
    required this.id,
    required this.createdBy,
    required this.createdAt,
    required this.deadline,
    required this.status,
    this.winningOptionId,
    this.resultMovieNightId,
    this.resolvedAt,
  });

  final String id;
  final String createdBy;
  final DateTime createdAt;

  /// Fester Zeitpunkt, ab dem keine Stimme mehr abgegeben/geändert werden
  /// darf (serverseitig über `firestore.rules` erzwungen, niemals nur
  /// clientseitig geprüft) und ab dem die Scheduled Cloud Function den
  /// Gewinner ermitteln darf.
  final DateTime deadline;

  /// `'open'` bis zur Auswertung durch die Scheduled Cloud Function,
  /// danach dauerhaft `'closed'` - niemals rückwirkend wieder `'open'`.
  final String status;

  bool get isOpen => status == 'open';

  /// ID des gewonnenen `MoviePollOption`-Dokuments - `null`, solange noch
  /// nicht ausgewertet ODER wenn niemand abgestimmt hat (kein Gewinner
  /// ermittelbar).
  final String? winningOptionId;

  /// ID des automatisch angelegten `movie_nights`-Dokuments (§12) mit dem
  /// Gewinner-Termin - `null`, solange noch nicht ausgewertet oder kein
  /// Gewinner ermittelbar war.
  final String? resultMovieNightId;

  final DateTime? resolvedAt;

  factory MoviePoll.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    final createdAtValue = data['created_at'];
    final deadlineValue = data['deadline'];
    final resolvedAtValue = data['resolved_at'];
    return MoviePoll(
      id: doc.id,
      createdBy: data['created_by'] as String? ?? '',
      createdAt: createdAtValue is Timestamp ? createdAtValue.toDate() : DateTime.now(),
      deadline: deadlineValue is Timestamp ? deadlineValue.toDate() : DateTime.now(),
      status: data['status'] as String? ?? 'open',
      winningOptionId: data['winning_option_id'] as String?,
      resultMovieNightId: data['result_movie_night_id'] as String?,
      resolvedAt: resolvedAtValue is Timestamp ? resolvedAtValue.toDate() : null,
    );
  }

  /// Felder für eine neue Abstimmung. `created_at` wird ausschließlich
  /// serverseitig gesetzt (`FieldValue.serverTimestamp()`); `status` startet
  /// immer als `'open'` - Gewinner-Felder sind zu diesem Zeitpunkt bewusst
  /// noch nicht Teil der Map (siehe `firestore.rules`: `hasOnly`).
  static Map<String, dynamic> toFirestoreCreate({
    required String createdBy,
    required DateTime deadline,
  }) {
    return {
      'created_by': createdBy,
      'created_at': FieldValue.serverTimestamp(),
      'deadline': Timestamp.fromDate(deadline),
      'status': 'open',
    };
  }
}
