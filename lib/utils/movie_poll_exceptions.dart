/// Wird geworfen, wenn eine Filmabend-Abstimmungs-Aktion (§21) aus
/// fachlichen Gründen nicht ausgeführt werden darf (z. B. kein Mitglied,
/// weniger als zwei Terminvorschläge, Deadline liegt nicht in der Zukunft,
/// Film ist kein Gruppen-Match, Abstimmung bereits ausgewertet). Kein
/// technischer Firestore-Fehler.
class MoviePollActionException implements Exception {
  const MoviePollActionException(this.message);

  final String message;

  @override
  String toString() => 'MoviePollActionException: $message';
}
