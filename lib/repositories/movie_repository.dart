import '../models/movie.dart';
import '../models/movie_cast.dart';
import '../models/movie_filter.dart';
import '../models/movie_page.dart';
import '../models/movie_trailer.dart';
import '../models/watch_provider_option.dart';
import '../services/tmdb_service.dart';
import '../utils/tmdb_config.dart';
import '../utils/tmdb_exceptions.dart';

/// Vermittelt zwischen [TmdbService] (rohes JSON) und dem Rest der App
/// (typisierte [Movie]s). Verantwortlich für Genre-Auflösung, Mapping und
/// einen einfachen In-Memory-Cache - TMDB bleibt die alleinige Datenquelle,
/// es wird nichts nach Firestore dupliziert.
class MovieRepository {
  MovieRepository(this._tmdbService);

  final TmdbService _tmdbService;

  Map<int, String>? _genreNamesCache;
  List<WatchProviderOption>? _watchProviderListCache;
  final Map<int, Movie> _detailsCache = {};
  static const _maxDetailsCacheSize = 100;
  final Map<int, MovieTrailer?> _trailerCache = {};
  static const _maxTrailerCacheSize = 100;
  final Map<int, List<int>> _castIdsCache = {};
  static const _maxCastIdsCacheSize = 100;

  Future<MoviePage> discoverMovies({int page = 1, MovieFilter filter = MovieFilter.empty}) async {
    final genreNames = await _genreNames();
    final json = await _tmdbService.discoverMovies(
      page: page,
      watchProviderId: filter.watchProviderId,
      genreIds: filter.genreIds,
      yearFrom: filter.yearFrom,
      yearTo: filter.yearTo,
      minRating: filter.minRating,
      runtimeFromMinutes: filter.runtimeFromMinutes,
      runtimeToMinutes: filter.runtimeToMinutes,
    );
    return _moviePageFromJson(json, genreNames);
  }

  /// Genres für die Filterauswahl (§10) - dieselbe TMDB-Genreliste, die auch
  /// intern für die Anzeige der Filmgenres verwendet wird.
  Future<Map<int, String>> getGenres() => _genreNames();

  /// Bei TMDB für die konfigurierte Region tatsächlich verfügbare
  /// Streaming-Anbieter (Abo/`flatrate`) - Grundlage der Plattform-Filter-
  /// Auswahl (§10). Kein selbst erfundenes Plattform-Set.
  Future<List<WatchProviderOption>> getAvailableWatchProviders({String? region}) async {
    final cached = _watchProviderListCache;
    if (cached != null) return cached;

    final json = await _tmdbService.watchProviderList(region: region);
    final results = json['results'];
    final providers = results is List
        ? results
            .whereType<Map<String, dynamic>>()
            .map(WatchProviderOption.fromTmdbJson)
            .where((provider) => provider.providerId != 0 && provider.providerName.isNotEmpty)
            .toList()
        : <WatchProviderOption>[];
    providers.sort((a, b) => a.providerName.compareTo(b.providerName));
    _watchProviderListCache = providers;
    return providers;
  }

  Future<MoviePage> searchMovies({required String query, int page = 1}) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) {
      return const MoviePage(movies: [], page: 1, totalPages: 0, totalResults: 0);
    }
    final genreNames = await _genreNames();
    final json = await _tmdbService.searchMovies(query: trimmedQuery, page: page);
    return _moviePageFromJson(json, genreNames);
  }

  Future<Movie> getMovieDetails(int tmdbId) async {
    final cached = _detailsCache[tmdbId];
    if (cached != null) return cached;

    final json = await _tmdbService.movieDetails(tmdbId);
    final movie = Movie.fromTmdbJson(json);

    if (_detailsCache.length >= _maxDetailsCacheSize) {
      _detailsCache.remove(_detailsCache.keys.first);
    }
    _detailsCache[tmdbId] = movie;
    return movie;
  }

  /// Streaming-Anbieter (Abo-Verfügbarkeit) für [region] (Standard: die in
  /// [TmdbConfig] konfigurierte Region). Liefert eine leere Liste, wenn für
  /// die Region keine Daten vorliegen - kein Fehler, da das ein normaler,
  /// häufiger Fall ist.
  Future<List<WatchProviderOption>> getWatchProviders(int tmdbId, {String? region}) async {
    final json = await _tmdbService.watchProviders(tmdbId);
    final results = json['results'];
    if (results is! Map<String, dynamic>) return const [];

    final regionData = results[region ?? TmdbConfig.defaultRegion];
    if (regionData is! Map<String, dynamic>) return const [];

    final flatrate = regionData['flatrate'];
    if (flatrate is! List) return const [];

    return flatrate
        .whereType<Map<String, dynamic>>()
        .map(WatchProviderOption.fromTmdbJson)
        .toList();
  }

  /// Trailer für den "Trailer ansehen"-Button (§9) - `null`, wenn TMDB
  /// keinen passenden YouTube-Trailer liefert (siehe
  /// [MovieTrailer.selectFromTmdbJson]). Der YouTube-Key wird nur für die
  /// Anzeige/Wiedergabe gehalten, nie nach Firestore dupliziert.
  Future<MovieTrailer?> getTrailer(int tmdbId) async {
    if (_trailerCache.containsKey(tmdbId)) return _trailerCache[tmdbId];

    final json = await _tmdbService.movieVideos(tmdbId);
    final trailer = MovieTrailer.selectFromTmdbJson(json);

    if (_trailerCache.length >= _maxTrailerCacheSize) {
      _trailerCache.remove(_trailerCache.keys.first);
    }
    _trailerCache[tmdbId] = trailer;
    return trailer;
  }

  /// Die Top-3-Hauptdarsteller-IDs eines Films für den Cast-Anti-Boost (§7,
  /// siehe [selectMainCastIds]) - gecached wie [getTrailer]/[getMovieDetails]
  /// (kein wiederholter TMDB-Request für bereits bekannte Filme). Wirft
  /// echte TMDB-Fehler durch statt sie zu verschlucken - die aufrufende
  /// Schicht (`SwipeQueueController`) entscheidet, wie mit einem
  /// fehlgeschlagenen Einzelfilm innerhalb einer größeren Kandidatenliste
  /// umgegangen wird (nicht die ganze Warteschlange blockieren).
  Future<List<int>> getMainCastIds(int tmdbId) async {
    final cached = _castIdsCache[tmdbId];
    if (cached != null) return cached;

    final json = await _tmdbService.movieCredits(tmdbId);
    final castIds = selectMainCastIds(json);

    if (_castIdsCache.length >= _maxCastIdsCacheSize) {
      _castIdsCache.remove(_castIdsCache.keys.first);
    }
    _castIdsCache[tmdbId] = castIds;
    return castIds;
  }

  Future<Map<int, String>> _genreNames() async {
    final cached = _genreNamesCache;
    if (cached != null) return cached;

    final json = await _tmdbService.genreList();
    final genres = json['genres'];
    final map = <int, String>{
      if (genres is List)
        for (final entry in genres.whereType<Map<String, dynamic>>())
          if (entry['id'] is num) (entry['id'] as num).toInt(): entry['name'] as String? ?? '',
    };
    _genreNamesCache = map;
    return map;
  }

  MoviePage _moviePageFromJson(Map<String, dynamic> json, Map<int, String> genreNames) {
    final results = json['results'];
    final movies = <Movie>[];
    if (results is List) {
      for (final entry in results.whereType<Map<String, dynamic>>()) {
        try {
          movies.add(Movie.fromTmdbJson(entry, genreNames: genreNames));
        } on TmdbInvalidResponseException {
          // Ein einzelnes defektes Element darf nicht die ganze Seite verwerfen.
          continue;
        }
      }
    }
    return MoviePage(
      movies: movies,
      page: (json['page'] as num?)?.toInt() ?? 1,
      totalPages: (json['total_pages'] as num?)?.toInt() ?? 0,
      totalResults: (json['total_results'] as num?)?.toInt() ?? 0,
    );
  }
}
