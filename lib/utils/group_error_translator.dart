import 'group_exceptions.dart';

/// Übersetzt technische Fehler aus dem Gruppen-System in verständliche,
/// deutsche Fehlermeldungen für die UI.
String translateGroupError(Object error) {
  if (error is GroupActionException) return error.message;
  return 'Etwas ist schiefgelaufen. Bitte versuche es erneut.';
}
