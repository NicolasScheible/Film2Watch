import 'tmdb_exceptions.dart';

/// Übersetzt technische TMDB-Fehler in verständliche, deutsche
/// Fehlermeldungen für die UI.
String translateTmdbError(Object error) {
  return switch (error) {
    TmdbNotConfiguredException() => 'TMDB API Key wird benötigt.',
    TmdbNetworkException() => 'Keine Internetverbindung. Bitte versuche es erneut.',
    TmdbUnauthorizedException() => 'Zugriff auf TMDB nicht möglich (ungültiger API-Zugang).',
    TmdbForbiddenException() => 'Zugriff auf TMDB wurde verweigert.',
    TmdbNotFoundException() => 'Dieser Film wurde nicht gefunden.',
    TmdbRateLimitException() => 'Zu viele Anfragen. Bitte warte einen Moment und versuche es erneut.',
    TmdbServerException() => 'TMDB ist aktuell nicht erreichbar. Bitte versuche es später erneut.',
    TmdbInvalidResponseException() => 'Die Filmdaten konnten nicht gelesen werden.',
    _ => 'Etwas ist schiefgelaufen. Bitte versuche es erneut.',
  };
}
