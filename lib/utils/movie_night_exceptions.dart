/// Wird geworfen, wenn eine Filmabend-Aktion (§12: "Filmabend planen") aus
/// fachlichen Gründen nicht ausgeführt werden darf (z. B. kein Mitglied,
/// keine Berechtigung zum Bearbeiten/Absagen, Film ist kein Gruppen-Match).
/// Kein technischer Firestore-Fehler.
class MovieNightActionException implements Exception {
  const MovieNightActionException(this.message);

  final String message;

  @override
  String toString() => 'MovieNightActionException: $message';
}
