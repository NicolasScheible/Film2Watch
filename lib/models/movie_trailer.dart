/// Ein YouTube-Trailer eines Films (TMDB `/movie/{id}/videos`, §9 der
/// Master-Spezifikation: "Trailer ansehen"-Button öffnet den YouTube-Trailer
/// als Popup). [youtubeKey] ist die YouTube-Video-ID, ausschließlich aus der
/// TMDB-Antwort - keine selbst konstruierte oder geratene URL.
class MovieTrailer {
  const MovieTrailer({required this.youtubeKey, required this.name});

  final String youtubeKey;
  final String name;

  /// Wählt aus TMDBs Video-Liste den für den "Trailer ansehen"-Button
  /// vorgesehenen Trailer aus, oder `null`, wenn kein passendes Video
  /// vorhanden ist. TMDB liefert unter `/videos` verschiedene Video-Typen
  /// (Trailer, Teaser, Clip, Featurette, ...) und mehrere Plattformen
  /// (YouTube, Vimeo) - §9 verlangt explizit einen YouTube-Trailer, daher:
  /// nur `site == 'YouTube'` und `type == 'Trailer'`; unter mehreren
  /// Treffern wird der offizielle bevorzugt, danach der zuletzt
  /// veröffentlichte (aktuellste Fassung, z. B. bei einem Re-Release).
  static MovieTrailer? selectFromTmdbJson(Map<String, dynamic> json) {
    final results = json['results'];
    if (results is! List) return null;

    final candidates = results
        .whereType<Map<String, dynamic>>()
        .where((video) =>
            video['site'] == 'YouTube' &&
            video['type'] == 'Trailer' &&
            video['key'] is String &&
            (video['key'] as String).isNotEmpty)
        .toList();
    if (candidates.isEmpty) return null;

    candidates.sort((a, b) {
      final officialA = a['official'] == true;
      final officialB = b['official'] == true;
      if (officialA != officialB) return officialA ? -1 : 1;
      final publishedA = _parseDate(a['published_at']);
      final publishedB = _parseDate(b['published_at']);
      if (publishedA == null || publishedB == null) return 0;
      return publishedB.compareTo(publishedA);
    });

    final best = candidates.first;
    return MovieTrailer(
      youtubeKey: best['key'] as String,
      name: best['name'] as String? ?? 'Trailer',
    );
  }

  static DateTime? _parseDate(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }
}
