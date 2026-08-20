/// Wird geworfen, wenn eine Chat-Aktion aus fachlichen Gründen nicht
/// ausgeführt werden darf (z. B. leere Nachricht, zu lang, kein Mitglied
/// mehr). Kein technischer Firestore-Fehler.
class ChatActionException implements Exception {
  const ChatActionException(this.message);

  final String message;

  @override
  String toString() => 'ChatActionException: $message';
}
