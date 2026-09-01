import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../utils/tmdb_config.dart';
import '../utils/tmdb_exceptions.dart';

/// Dünner Client für die TMDB-API v3. Kennt keine App-/Movie-Modelle -
/// gibt rohe, aber HTTP-fehlergeprüfte JSON-Maps zurück. Das Mapping auf
/// interne Modelle übernimmt [MovieRepository].
///
/// Der [accessToken] wird injiziert statt intern aus [TmdbConfig] gelesen,
/// damit die Fehlerbehandlung in Tests unabhängig von `--dart-define`
/// geprüft werden kann.
class TmdbService {
  TmdbService(this._client, {required this.accessToken});

  final http.Client _client;
  final String accessToken;

  static const _baseUrl = 'https://api.themoviedb.org/3';
  static const _timeout = Duration(seconds: 10);

  /// [watchProviderId], [genreIds] (ODER-verknüpft, TMDB-Pipe-Syntax),
  /// [yearFrom]/[yearTo] (über `primary_release_date.gte`/`.lte`),
  /// [minRating] (`vote_average.gte`) und [runtimeFromMinutes]/
  /// [runtimeToMinutes] (`with_runtime.gte`/`.lte`) sind optionale
  /// TMDB-Discover-Filter (§10 der Master-Spezifikation) - werden nur
  /// gesendet, wenn tatsächlich gesetzt.
  Future<Map<String, dynamic>> discoverMovies({
    required int page,
    String? language,
    String? region,
    int? watchProviderId,
    Set<int>? genreIds,
    int? yearFrom,
    int? yearTo,
    double? minRating,
    int? runtimeFromMinutes,
    int? runtimeToMinutes,
  }) {
    final effectiveRegion = region ?? TmdbConfig.defaultRegion;
    return _get('/discover/movie', {
      'page': '$page',
      'language': language ?? TmdbConfig.defaultLanguage,
      'region': effectiveRegion,
      'sort_by': 'popularity.desc',
      'include_adult': 'false',
      if (watchProviderId != null) 'with_watch_providers': '$watchProviderId',
      if (watchProviderId != null) 'watch_region': effectiveRegion,
      if (watchProviderId != null) 'with_watch_monetization_types': 'flatrate',
      if (genreIds != null && genreIds.isNotEmpty) 'with_genres': genreIds.join('|'),
      if (yearFrom != null) 'primary_release_date.gte': '$yearFrom-01-01',
      if (yearTo != null) 'primary_release_date.lte': '$yearTo-12-31',
      if (minRating != null && minRating > 0) 'vote_average.gte': '$minRating',
      if (runtimeFromMinutes != null) 'with_runtime.gte': '$runtimeFromMinutes',
      if (runtimeToMinutes != null) 'with_runtime.lte': '$runtimeToMinutes',
    });
  }

  /// Liste der bei TMDB für [region] verfügbaren Streaming-Anbieter
  /// (`/watch/providers/movie`) - Grundlage für die Plattform-Filter-Auswahl
  /// (§10). Echte TMDB-Daten statt einer selbst erfundenen Plattformliste.
  Future<Map<String, dynamic>> watchProviderList({String? region}) {
    return _get('/watch/providers/movie', {
      'watch_region': region ?? TmdbConfig.defaultRegion,
    });
  }

  Future<Map<String, dynamic>> searchMovies({
    required String query,
    required int page,
    String? language,
  }) {
    return _get('/search/movie', {
      'query': query,
      'page': '$page',
      'language': language ?? TmdbConfig.defaultLanguage,
      'include_adult': 'false',
    });
  }

  Future<Map<String, dynamic>> movieDetails(int tmdbId, {String? language}) {
    return _get('/movie/$tmdbId', {
      'language': language ?? TmdbConfig.defaultLanguage,
    });
  }

  Future<Map<String, dynamic>> genreList({String? language}) {
    return _get('/genre/movie/list', {
      'language': language ?? TmdbConfig.defaultLanguage,
    });
  }

  Future<Map<String, dynamic>> watchProviders(int tmdbId) {
    return _get('/movie/$tmdbId/watch/providers', const {});
  }

  /// Trailer-/Video-Liste eines Films (`/movie/{id}/videos`) - Grundlage für
  /// den "Trailer ansehen"-Button (§9). Liefert u. a. YouTube-Video-Keys.
  Future<Map<String, dynamic>> movieVideos(int tmdbId, {String? language}) {
    return _get('/movie/$tmdbId/videos', {
      'language': language ?? TmdbConfig.defaultLanguage,
    });
  }

  /// Besetzung eines Films (`/movie/{id}/credits`) - Grundlage für den
  /// Cast-Anti-Boost (§7: "gleicher Hauptdarsteller"). TMDB liefert das
  /// `cast`-Array bereits aufsteigend nach `order` sortiert (0 = am
  /// prominentesten billed) - keine eigene Sortierung nötig. Kein
  /// `language`-Parameter, da für den Boost ausschließlich die numerischen
  /// Personen-IDs relevant sind, keine (lokalisierten) Namen.
  Future<Map<String, dynamic>> movieCredits(int tmdbId) {
    return _get('/movie/$tmdbId/credits', const {});
  }

  Future<Map<String, dynamic>> _get(String path, Map<String, String> queryParameters) async {
    if (accessToken.isEmpty) {
      throw const TmdbNotConfiguredException();
    }

    final uri = Uri.parse('$_baseUrl$path').replace(queryParameters: queryParameters);

    final http.Response response;
    try {
      response = await _client.get(
        uri,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Accept': 'application/json',
        },
      ).timeout(_timeout);
    } on TimeoutException {
      throw const TmdbNetworkException('Zeitüberschreitung bei der Verbindung zu TMDB.');
    } on SocketException {
      throw const TmdbNetworkException('Keine Internetverbindung.');
    } on http.ClientException catch (e) {
      throw TmdbNetworkException('Netzwerkfehler: ${e.message}');
    }

    return _decodeResponse(response);
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    switch (response.statusCode) {
      case 200:
        return _decodeJsonMap(response.body);
      case 401:
        throw const TmdbUnauthorizedException('TMDB-Zugang ist ungültig oder abgelaufen.');
      case 403:
        throw const TmdbForbiddenException('Zugriff auf TMDB wurde verweigert.');
      case 404:
        throw const TmdbNotFoundException('Ressource wurde bei TMDB nicht gefunden.');
      case 429:
        throw const TmdbRateLimitException('TMDB Rate Limit erreicht.');
      default:
        if (response.statusCode >= 500) {
          throw TmdbServerException('TMDB-Serverfehler (${response.statusCode}).');
        }
        throw TmdbInvalidResponseException('Unerwarteter TMDB-Statuscode ${response.statusCode}.');
    }
  }

  Map<String, dynamic> _decodeJsonMap(String body) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw const TmdbInvalidResponseException('TMDB-Antwort enthält kein gültiges JSON.');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const TmdbInvalidResponseException('TMDB-Antwort hat ein unerwartetes Format.');
    }
    return decoded;
  }
}
