import 'package:firebase_core/firebase_core.dart';

import 'profile_image_exceptions.dart';

/// Übersetzt technische Fehler rund um den Profilbild-Upload in
/// verständliche, deutsche Fehlermeldungen für die UI.
String translateProfileImageError(Object error) {
  if (error is ProfileImageException) return error.message;
  if (error is FirebaseException) {
    switch (error.code) {
      case 'unauthorized':
        return 'Du hast keine Berechtigung, dieses Bild zu ändern.';
      case 'canceled':
        return 'Der Upload wurde abgebrochen.';
      case 'object-not-found':
        return 'Die Datei wurde nicht gefunden.';
      case 'network-request-failed':
      case 'retry-limit-exceeded':
        return 'Netzwerkproblem. Bitte überprüfe deine Internetverbindung.';
      default:
        return 'Das Profilbild konnte nicht gespeichert werden. Bitte versuche es erneut.';
    }
  }
  return 'Etwas ist schiefgelaufen. Bitte versuche es erneut.';
}
