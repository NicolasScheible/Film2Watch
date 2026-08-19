/// Wird geworfen, wenn eine Freundes-Aktion aus fachlichen Gründen nicht
/// ausgeführt werden darf (z. B. bereits Freunde, eigener Code, bereits
/// angefragt). Kein technischer Firestore-Fehler, sondern eine bewusste,
/// verständliche Ablehnung durch die Anwendungslogik.
class FriendActionException implements Exception {
  const FriendActionException(this.message);

  final String message;

  @override
  String toString() => 'FriendActionException: $message';
}
