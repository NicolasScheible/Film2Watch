import 'package:cloud_firestore/cloud_firestore.dart';

/// Eine einzelne Stimme innerhalb einer Filmabend-Abstimmung (§21): "dieser
/// User stimmt für diesen Terminvorschlag". Ein User kann mehrere Stimmen in
/// derselben Abstimmung haben (Doodle-Prinzip: mehrere passende Optionen
/// auswählen) - aber nie zweimal für dieselbe Option, siehe Dokument-ID.
///
/// `groups/{groupId}/movie_night_polls/{pollId}/votes/{voteId}`. Dokument-ID
/// ist deterministisch `"{uid}_{optionId}"` (analog zu
/// `groups/{groupId}/swipes/{uid}_{movieId}`) - verhindert Duplikate für
/// dieselbe (User, Option)-Kombination strukturell, ohne eine zusätzliche
/// Abfrage. Ein Ändern der Stimme läuft über Löschen der nicht mehr
/// gewählten und Anlegen der neu gewählten Options-Stimmen (siehe
/// `MoviePollRepository.setMyVotes`) - es gibt bewusst keine
/// Abstimmungshistorie.
class MoviePollVote {
  const MoviePollVote({required this.id, required this.uid, required this.optionId});

  final String id;
  final String uid;
  final String optionId;

  factory MoviePollVote.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return MoviePollVote(
      id: doc.id,
      uid: data['uid'] as String? ?? '',
      optionId: data['option_id'] as String? ?? '',
    );
  }

  static String idFor({required String uid, required String optionId}) => '${uid}_$optionId';

  static Map<String, dynamic> toFirestoreCreate({required String uid, required String optionId}) {
    return {'uid': uid, 'option_id': optionId, 'voted_at': FieldValue.serverTimestamp()};
  }
}
