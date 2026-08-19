import 'friend_exceptions.dart';

/// Übersetzt technische Fehler aus dem Freundesystem in verständliche,
/// deutsche Fehlermeldungen für die UI.
String translateFriendError(Object error) {
  if (error is FriendActionException) return error.message;
  return 'Etwas ist schiefgelaufen. Bitte versuche es erneut.';
}
