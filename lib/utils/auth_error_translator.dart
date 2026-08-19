import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'auth_exceptions.dart';

/// Übersetzt technische Auth-Fehler (Firebase, Google, Apple) in
/// verständliche, deutsche Fehlermeldungen für die UI.
String translateAuthError(Object error) {
  if (error is FirebaseAuthException) {
    return _translateFirebaseAuthError(error);
  }
  if (error is AuthConfigurationException) {
    return error.message;
  }
  if (error is GoogleSignInException) {
    return _translateGoogleSignInError(error);
  }
  if (error is SignInWithAppleAuthorizationException) {
    if (error.code == AuthorizationErrorCode.canceled) {
      return 'Die Apple-Anmeldung wurde abgebrochen.';
    }
    return 'Die Apple-Anmeldung ist fehlgeschlagen. Bitte versuche es erneut.';
  }
  if (error is SignInWithAppleException) {
    return 'Die Apple-Anmeldung ist aktuell nicht verfügbar.';
  }
  return 'Etwas ist schiefgelaufen. Bitte versuche es erneut.';
}

String _translateFirebaseAuthError(FirebaseAuthException error) {
  switch (error.code) {
    case 'invalid-email':
      return 'Bitte gib eine gültige E-Mail-Adresse ein.';
    case 'user-disabled':
      return 'Dieser Account wurde deaktiviert.';
    case 'user-not-found':
      return 'Es existiert kein Account mit dieser E-Mail-Adresse.';
    case 'wrong-password':
      return 'Das Passwort ist falsch.';
    case 'invalid-credential':
      return 'E-Mail-Adresse oder Passwort sind falsch.';
    case 'email-already-in-use':
      return 'Diese E-Mail-Adresse ist bereits registriert.';
    case 'weak-password':
      return 'Das Passwort ist zu schwach. Bitte wähle ein stärkeres Passwort.';
    case 'operation-not-allowed':
      return 'Diese Anmeldemethode ist aktuell nicht verfügbar.';
    case 'too-many-requests':
      return 'Zu viele Versuche. Bitte warte einen Moment und versuche es erneut.';
    case 'network-request-failed':
      return 'Netzwerkproblem. Bitte überprüfe deine Internetverbindung.';
    case 'requires-recent-login':
      return 'Bitte melde dich erneut an, um fortzufahren.';
    case 'account-exists-with-different-credential':
      return 'Diese E-Mail-Adresse ist bereits mit einer anderen Anmeldemethode verknüpft.';
    default:
      return 'Anmeldung fehlgeschlagen. Bitte versuche es erneut.';
  }
}

String _translateGoogleSignInError(GoogleSignInException error) {
  switch (error.code) {
    case GoogleSignInExceptionCode.canceled:
      return 'Die Google-Anmeldung wurde abgebrochen.';
    case GoogleSignInExceptionCode.clientConfigurationError:
    case GoogleSignInExceptionCode.providerConfigurationError:
      return 'Die Google-Anmeldung ist aktuell noch nicht vollständig eingerichtet.';
    default:
      return 'Die Google-Anmeldung ist fehlgeschlagen. Bitte versuche es erneut.';
  }
}
