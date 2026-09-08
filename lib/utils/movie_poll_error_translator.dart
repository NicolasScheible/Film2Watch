import 'movie_poll_exceptions.dart';

/// Übersetzt technische Fehler aus dem Filmabend-Abstimmungs-System (§21) in
/// verständliche, deutsche Fehlermeldungen für die UI.
String translateMoviePollError(Object error) {
  if (error is MoviePollActionException) return error.message;
  return 'Etwas ist schiefgelaufen. Bitte versuche es erneut.';
}
