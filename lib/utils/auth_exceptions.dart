/// Wird geworfen, wenn eine Auth-Methode aufgrund fehlender technischer
/// Konfiguration (z. B. fehlender OAuth-Client) nicht ausgeführt werden kann.
///
/// Dies ist keine Fake-Login-Logik, sondern eine ehrliche, typisierte
/// Fehlermeldung für einen echten, aktuell nicht nutzbaren Login-Weg.
class AuthConfigurationException implements Exception {
  const AuthConfigurationException(this.message);

  final String message;

  @override
  String toString() => 'AuthConfigurationException: $message';
}
