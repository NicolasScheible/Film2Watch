import '../utils/tmdb_exceptions.dart';

/// Internes Film-Modell - der Rest der App arbeitet ausschließlich hiermit,
/// nicht mit rohen TMDB-JSON-Maps.
class Movie {
  const Movie({
    required this.tmdbId,
    required this.title,
    required this.originalTitle,
    required this.overview,
    required this.posterPath,
    required this.backdropPath,
    required this.releaseDate,
    required this.genreIds,
    required this.genres,
    required this.voteAverage,
    required this.voteCount,
    required this.runtime,
    required this.originalLanguage,
    this.castIds = const [],
  });

  final int tmdbId;
  final String title;
  final String originalTitle;
  final String overview;
  final String? posterPath;
  final String? backdropPath;
  final DateTime? releaseDate;
  final List<int> genreIds;
  final List<String> genres;
  final double voteAverage;
  final int voteCount;
  final int? runtime;
  final String originalLanguage;

  /// Die Hauptdarsteller-IDs (§7 Cast-Anti-Boost, siehe
  /// `selectMainCastIds`) - anders als [genreIds] NICHT Teil der
  /// Discover-/Search-/Details-Antwort, die dieses [Movie] erzeugt hat
  /// (TMDB liefert Cast nur über den separaten `/credits`-Endpunkt). Leer,
  /// bis [withCastIds] es explizit setzt (siehe `SwipeQueueController`, das
  /// Kandidaten vor der Boost-Sortierung damit anreichert).
  final List<int> castIds;

  /// Liefert eine Kopie mit gesetzten [castIds] - alle anderen Felder
  /// unverändert. Kein allgemeines `copyWith`, da aktuell nur dieses eine
  /// Feld nachträglich angereichert werden muss.
  Movie withCastIds(List<int> castIds) {
    return Movie(
      tmdbId: tmdbId,
      title: title,
      originalTitle: originalTitle,
      overview: overview,
      posterPath: posterPath,
      backdropPath: backdropPath,
      releaseDate: releaseDate,
      genreIds: genreIds,
      genres: genres,
      voteAverage: voteAverage,
      voteCount: voteCount,
      runtime: runtime,
      originalLanguage: originalLanguage,
      castIds: castIds,
    );
  }

  /// Baut ein [Movie] aus einer TMDB-JSON-Antwort (Discover/Search/Details).
  ///
  /// [genreNames] ist die id→name-Zuordnung aus `/genre/movie/list`, die für
  /// Discover/Search-Ergebnisse benötigt wird (die dort nur `genre_ids`
  /// liefern). Enthält das JSON bereits vollständige `genres`-Objekte (wie
  /// bei den Movie-Details), werden diese direkt verwendet.
  ///
  /// Wirft [TmdbInvalidResponseException], wenn zwingend benötigte Felder
  /// (id, title) fehlen oder einen unerwarteten Typ haben. Alle anderen
  /// Felder sind robust gegen fehlende/ungültige Werte.
  factory Movie.fromTmdbJson(
    Map<String, dynamic> json, {
    Map<int, String> genreNames = const {},
  }) {
    final rawId = json['id'];
    if (rawId is! num) {
      throw const TmdbInvalidResponseException('TMDB-Antwort enthält keine gültige Film-ID.');
    }
    final rawTitle = json['title'];
    if (rawTitle is! String || rawTitle.isEmpty) {
      throw const TmdbInvalidResponseException('TMDB-Antwort enthält keinen gültigen Filmtitel.');
    }

    final genreIds = (json['genre_ids'] as List?)
            ?.whereType<num>()
            .map((n) => n.toInt())
            .toList() ??
        const [];

    final genreObjects = json['genres'] as List?;
    final genres = genreObjects != null
        ? genreObjects
            .whereType<Map<String, dynamic>>()
            .map((g) => g['name'] as String?)
            .whereType<String>()
            .where((name) => name.isNotEmpty)
            .toList()
        : genreIds.map((id) => genreNames[id]).whereType<String>().toList();

    return Movie(
      tmdbId: rawId.toInt(),
      title: rawTitle,
      originalTitle: json['original_title'] as String? ?? rawTitle,
      overview: json['overview'] as String? ?? '',
      posterPath: json['poster_path'] as String?,
      backdropPath: json['backdrop_path'] as String?,
      releaseDate: _parseDate(json['release_date']),
      genreIds: genreIds,
      genres: genres,
      voteAverage: (json['vote_average'] as num?)?.toDouble() ?? 0.0,
      voteCount: (json['vote_count'] as num?)?.toInt() ?? 0,
      runtime: (json['runtime'] as num?)?.toInt(),
      originalLanguage: json['original_language'] as String? ?? '',
    );
  }

  static DateTime? _parseDate(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }
}
