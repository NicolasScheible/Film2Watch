import 'movie_night_exceptions.dart';

/// Übersetzt technische Fehler aus dem Filmabend-System in verständliche,
/// deutsche Fehlermeldungen für die UI.
String translateMovieNightError(Object error) {
  if (error is MovieNightActionException) return error.message;
  return 'Etwas ist schiefgelaufen. Bitte versuche es erneut.';
}
