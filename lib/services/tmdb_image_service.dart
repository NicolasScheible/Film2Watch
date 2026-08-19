/// Verfügbare TMDB-Bildgrößen (siehe https://developer.themoviedb.org/docs/image-basics).
enum TmdbImageSize {
  w92('w92'),
  w154('w154'),
  w185('w185'),
  w342('w342'),
  w500('w500'),
  w780('w780'),
  w1280('w1280'),
  original('original');

  const TmdbImageSize(this.value);
  final String value;
}

/// Zentrale Stelle zum Aufbau von TMDB-Bild-URLs aus den von der API
/// gelieferten relativen Pfaden - keine manuell zusammengebauten URL-Strings
/// an anderer Stelle im Code.
abstract final class TmdbImageService {
  static const _baseUrl = 'https://image.tmdb.org/t/p/';

  static String? posterUrl(String? path, {TmdbImageSize size = TmdbImageSize.w500}) {
    return _buildUrl(path, size);
  }

  static String? backdropUrl(String? path, {TmdbImageSize size = TmdbImageSize.w1280}) {
    return _buildUrl(path, size);
  }

  static String? providerLogoUrl(String? path, {TmdbImageSize size = TmdbImageSize.w92}) {
    return _buildUrl(path, size);
  }

  static String? _buildUrl(String? path, TmdbImageSize size) {
    if (path == null || path.isEmpty) return null;
    return '$_baseUrl${size.value}$path';
  }
}
