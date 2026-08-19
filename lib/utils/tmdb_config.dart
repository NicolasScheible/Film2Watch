/// TMDB-Konfiguration. Der Access Token wird ausschließlich zur Build-Zeit
/// über `--dart-define=TMDB_ACCESS_TOKEN=...` injiziert - niemals im
/// Quellcode hinterlegt. Sprache/Region sind ebenfalls per `--dart-define`
/// überschreibbar (z. B. für andere Regionen als Deutschland), ohne dass
/// dafür eine Einstellungs-UI existieren muss.
abstract final class TmdbConfig {
  static const accessToken = String.fromEnvironment('TMDB_ACCESS_TOKEN');
  static const defaultLanguage = String.fromEnvironment(
    'TMDB_LANGUAGE',
    defaultValue: 'de-DE',
  );
  static const defaultRegion = String.fromEnvironment(
    'TMDB_REGION',
    defaultValue: 'DE',
  );

  static bool get isConfigured => accessToken.isNotEmpty;
}
