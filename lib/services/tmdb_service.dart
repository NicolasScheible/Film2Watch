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

  Future<Map<String, dynamic>> discoverMovies({
    required int page,
    String? language,
    String? region,
  }) {
    return _get('/discover/movie', {
      'page': '$page',
      'language': language ?? TmdbConfig.defaultLanguage,
      'region': region ?? TmdbConfig.defaultRegion,
      'sort_by': 'popularity.desc',
      'include_adult': 'false',
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
