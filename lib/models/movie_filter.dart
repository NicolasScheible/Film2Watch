/// Filter für die TMDB-Discover-Filmauswahl in der Swipe-Warteschlange
/// (§10 der Master-Spezifikation: Plattform-Filter als "zentrales
/// Alleinstellungsmerkmal", außerdem Genre, Erscheinungsjahr, Bewertung,
/// Filmlänge). Rein clientseitige, session-lokale Einstellung - die
/// Master-Spezifikation verlangt an keiner Stelle eine dauerhafte
/// Speicherung, daher kein Firestore-Feld/keine eigene Collection dafür.
///
/// `null` bei einer Grenze bedeutet "kein Filter aktiv" für dieses
/// Kriterium - unterscheidet sich bewusst von einem gewählten Extremwert
/// (z. B. "mindestens 0.0 Bewertung" wäre technisch identisch mit "kein
/// Filter", spart aber keine zusätzliche Fallunterscheidung beim Aufbau der
/// TMDB-Query).
class MovieFilter {
  const MovieFilter({
    this.watchProviderId,
    this.genreIds = const {},
    this.yearFrom,
    this.yearTo,
    this.minRating,
    this.runtimeFromMinutes,
    this.runtimeToMinutes,
  });

  /// TMDB `provider_id` einer einzelnen Streaming-Plattform. Einzelauswahl
  /// im MVP (Mehrfachauswahl ist laut §15 ein Premium-Feature) - `null`
  /// bedeutet "alle Plattformen" (kein Filter).
  final int? watchProviderId;

  /// TMDB Genre-IDs. Mehrere Genres werden mit ODER verknüpft (ein Film
  /// muss mindestens eines der gewählten Genres haben).
  final Set<int> genreIds;

  final int? yearFrom;
  final int? yearTo;

  /// Mindestbewertung auf der nativen TMDB-`vote_average`-Skala (0–10).
  final double? minRating;

  final int? runtimeFromMinutes;
  final int? runtimeToMinutes;

  bool get isActive =>
      watchProviderId != null ||
      genreIds.isNotEmpty ||
      yearFrom != null ||
      yearTo != null ||
      (minRating != null && minRating! > 0) ||
      runtimeFromMinutes != null ||
      runtimeToMinutes != null;

  /// Anzahl der aktiven Filterkriterien - für ein Badge in der UI.
  int get activeCount => [
        watchProviderId != null,
        genreIds.isNotEmpty,
        yearFrom != null || yearTo != null,
        minRating != null && minRating! > 0,
        runtimeFromMinutes != null || runtimeToMinutes != null,
      ].where((active) => active).length;

  static const MovieFilter empty = MovieFilter();

  MovieFilter copyWith({
    int? watchProviderId,
    bool clearWatchProviderId = false,
    Set<int>? genreIds,
    int? yearFrom,
    bool clearYearFrom = false,
    int? yearTo,
    bool clearYearTo = false,
    double? minRating,
    bool clearMinRating = false,
    int? runtimeFromMinutes,
    bool clearRuntimeFromMinutes = false,
    int? runtimeToMinutes,
    bool clearRuntimeToMinutes = false,
  }) {
    return MovieFilter(
      watchProviderId: clearWatchProviderId ? null : (watchProviderId ?? this.watchProviderId),
      genreIds: genreIds ?? this.genreIds,
      yearFrom: clearYearFrom ? null : (yearFrom ?? this.yearFrom),
      yearTo: clearYearTo ? null : (yearTo ?? this.yearTo),
      minRating: clearMinRating ? null : (minRating ?? this.minRating),
      runtimeFromMinutes:
          clearRuntimeFromMinutes ? null : (runtimeFromMinutes ?? this.runtimeFromMinutes),
      runtimeToMinutes: clearRuntimeToMinutes ? null : (runtimeToMinutes ?? this.runtimeToMinutes),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MovieFilter &&
      other.watchProviderId == watchProviderId &&
      other.genreIds.length == genreIds.length &&
      other.genreIds.containsAll(genreIds) &&
      other.yearFrom == yearFrom &&
      other.yearTo == yearTo &&
      other.minRating == minRating &&
      other.runtimeFromMinutes == runtimeFromMinutes &&
      other.runtimeToMinutes == runtimeToMinutes;

  @override
  int get hashCode => Object.hash(
        watchProviderId,
        Object.hashAllUnordered(genreIds),
        yearFrom,
        yearTo,
        minRating,
        runtimeFromMinutes,
        runtimeToMinutes,
      );
}
