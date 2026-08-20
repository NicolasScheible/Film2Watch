import 'chat_exceptions.dart';

/// Übersetzt technische Fehler aus dem Chat-System in verständliche,
/// deutsche Fehlermeldungen für die UI.
String translateChatError(Object error) {
  if (error is ChatActionException) return error.message;
  return 'Nachricht konnte nicht gesendet werden. Bitte versuche es erneut.';
}
