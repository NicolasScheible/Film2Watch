/// Wird geworfen, wenn eine Gruppen-Aktion aus fachlichen Gründen nicht
/// ausgeführt werden darf (z. B. Admin muss vor dem Verlassen einen neuen
/// Admin bestimmen, Nicht-Freund kann nicht eingeladen werden). Kein
/// technischer Firestore-Fehler.
class GroupActionException implements Exception {
  const GroupActionException(this.message);

  final String message;

  @override
  String toString() => 'GroupActionException: $message';
}
