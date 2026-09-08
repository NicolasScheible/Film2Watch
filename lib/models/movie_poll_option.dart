import 'package:cloud_firestore/cloud_firestore.dart';

/// Ein einzelner Terminvorschlag innerhalb einer Filmabend-Abstimmung (§21).
/// Dieselben Felder wie ein `MovieNight`-Termin (Datum/Uhrzeit/Plattform +
/// optional ein bereits gematchter Film) - bewusst keine neue, eigene
/// Terminmodellierung.
///
/// `groups/{groupId}/movie_night_polls/{pollId}/options/{optionId}`,
/// Firestore Auto-ID. Nach dem Anlegen unveränderlich (`firestore.rules`:
/// `allow update: if false`) - Optionen entstehen ausschließlich zusammen
/// mit der Abstimmung selbst, ein nachträgliches Hinzufügen/Ändern ist kein
/// Teil dieses Schritts.
class MoviePollOption {
  const MoviePollOption({
    required this.id,
    required this.scheduledAt,
    required this.platformId,
    this.movieId,
  });

  final String id;
  final DateTime scheduledAt;
  final int platformId;
  final int? movieId;

  factory MoviePollOption.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    final scheduledAtValue = data['scheduled_at'];
    return MoviePollOption(
      id: doc.id,
      scheduledAt: scheduledAtValue is Timestamp ? scheduledAtValue.toDate() : DateTime.now(),
      platformId: (data['platform_id'] as num?)?.toInt() ?? 0,
      movieId: (data['movie_id'] as num?)?.toInt(),
    );
  }

  static Map<String, dynamic> toFirestoreCreate({
    required DateTime scheduledAt,
    required int platformId,
    int? movieId,
  }) {
    return {
      'scheduled_at': Timestamp.fromDate(scheduledAt),
      'platform_id': platformId,
      'movie_id': ?movieId,
    };
  }
}
