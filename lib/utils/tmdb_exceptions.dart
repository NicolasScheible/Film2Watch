/// Fehler rund um die TMDB-Integration. Kein technischer HTTP-Fehler wird
/// ungefiltert an die UI durchgereicht - siehe `tmdb_error_translator.dart`.
sealed class TmdbException implements Exception {
  const TmdbException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Kein TMDB Access Token konfiguriert (`--dart-define=TMDB_ACCESS_TOKEN=...`).
class TmdbNotConfiguredException extends TmdbException {
  const TmdbNotConfiguredException() : super('TMDB API Key wird benötigt.');
}

/// Keine Internetverbindung oder Zeitüberschreitung.
class TmdbNetworkException extends TmdbException {
  const TmdbNetworkException(super.message);
}

/// HTTP 401 - Access Token ungültig/abgelaufen.
class TmdbUnauthorizedException extends TmdbException {
  const TmdbUnauthorizedException(super.message);
}

/// HTTP 403 - Zugriff verweigert.
class TmdbForbiddenException extends TmdbException {
  const TmdbForbiddenException(super.message);
}

/// HTTP 404 - Ressource nicht gefunden.
class TmdbNotFoundException extends TmdbException {
  const TmdbNotFoundException(super.message);
}

/// HTTP 429 - Rate Limit erreicht.
class TmdbRateLimitException extends TmdbException {
  const TmdbRateLimitException(super.message);
}

/// HTTP 5xx - TMDB-Serverfehler.
class TmdbServerException extends TmdbException {
  const TmdbServerException(super.message);
}

/// Unerwarteter Statuscode oder ungültiges/unvollständiges JSON.
class TmdbInvalidResponseException extends TmdbException {
  const TmdbInvalidResponseException(super.message);
}
