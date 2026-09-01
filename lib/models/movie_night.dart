import 'package:cloud_firestore/cloud_firestore.dart';

/// Ein geplanter Filmabend (§12 der Master-Spezifikation: "Filmabend planen"
/// - Datum/Uhrzeit/Plattform + Reminder-Push). Bewusst NICHT die komplexere,
/// mit dem Produktverantwortlichen ausdrücklich zurückgestellte
/// "Filmabend-Abstimmung" (§21: Doodle-artige Mehrfachoptionen-Abstimmung
/// unter den Mitgliedern) - kein Voting, kein RSVP, nur ein einzelner
/// Terminvorschlag.
///
/// `groups/{groupId}/movie_nights/{movieNightId}`, Firestore Auto-ID (eine
/// Gruppe kann mehrere geplante Filmabende gleichzeitig haben, analog zu
/// `messages`).
class MovieNight {
  const MovieNight({
    required this.id,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    required this.scheduledAt,
    required this.platformId,
    this.movieId,
  });

  final String id;

  /// Nach dem Anlegen unveränderlich - wer einen Filmabend bearbeiten/
  /// absagen darf, wird dagegen geprüft (Ersteller oder Gruppen-Admin).
  final String createdBy;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// Datum + Uhrzeit des Filmabends als ein kombinierter Zeitpunkt - §12
  /// nennt "Datum" und "Uhrzeit" als zusammengehörige Angabe, keine zwei
  /// unabhängig speicherbaren Werte.
  final DateTime scheduledAt;

  /// TMDB `provider_id` der vorgeschlagenen Streaming-Plattform (§12:
  /// "Plattform") - derselbe, bereits bestehende Plattform-Begriff wie im
  /// Filter-System (§10, `MovieFilter.watchProviderId`/`WatchProviderOption`),
  /// keine neue, eigene Plattform-Modellierung.
  final int platformId;

  /// Optional: ein bereits gematchter Film der Gruppe (mit dem
  /// Produktverantwortlichen abgestimmt - kein Pflichtfeld, und falls
  /// gesetzt ausschließlich ein bestehendes Gruppen-Match, kein beliebiger
  /// TMDB-Film). `null` bedeutet "noch kein Film festgelegt".
  final int? movieId;

  factory MovieNight.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    final createdAtValue = data['created_at'];
    final updatedAtValue = data['updated_at'];
    final scheduledAtValue = data['scheduled_at'];
    return MovieNight(
      id: doc.id,
      createdBy: data['created_by'] as String? ?? '',
      createdAt: createdAtValue is Timestamp ? createdAtValue.toDate() : DateTime.now(),
      updatedAt: updatedAtValue is Timestamp ? updatedAtValue.toDate() : DateTime.now(),
      scheduledAt: scheduledAtValue is Timestamp ? scheduledAtValue.toDate() : DateTime.now(),
      platformId: (data['platform_id'] as num?)?.toInt() ?? 0,
      movieId: (data['movie_id'] as num?)?.toInt(),
    );
  }

  /// Felder für einen neuen Filmabend. `created_at`/`updated_at` werden
  /// ausschließlich serverseitig gesetzt (`FieldValue.serverTimestamp()`) -
  /// die lokale Gerätezeit ist keine vertrauenswürdige Quelle.
  static Map<String, dynamic> toFirestoreCreate({
    required String createdBy,
    required DateTime scheduledAt,
    required int platformId,
    int? movieId,
  }) {
    return {
      'created_by': createdBy,
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
      'scheduled_at': Timestamp.fromDate(scheduledAt),
      'platform_id': platformId,
      'movie_id': ?movieId,
    };
  }

  /// Felder für ein Update eines bestehenden Filmabends - `created_by`/
  /// `created_at` bleiben unveränderlich (nicht Teil dieser Map, siehe
  /// Firestore Rules).
  static Map<String, dynamic> toFirestoreUpdate({
    required DateTime scheduledAt,
    required int platformId,
    int? movieId,
  }) {
    return {
      'updated_at': FieldValue.serverTimestamp(),
      'scheduled_at': Timestamp.fromDate(scheduledAt),
      'platform_id': platformId,
      if (movieId != null) 'movie_id': movieId else 'movie_id': FieldValue.delete(),
    };
  }
}
