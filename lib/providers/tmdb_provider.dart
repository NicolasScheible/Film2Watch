import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../models/movie.dart';
import '../models/movie_trailer.dart';
import '../models/watch_provider_option.dart';
import '../repositories/movie_repository.dart';
import '../services/tmdb_service.dart';
import '../utils/tmdb_config.dart';

final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final tmdbServiceProvider = Provider<TmdbService>((ref) {
  return TmdbService(ref.watch(httpClientProvider), accessToken: TmdbConfig.accessToken);
});

final movieRepositoryProvider = Provider<MovieRepository>((ref) {
  return MovieRepository(ref.watch(tmdbServiceProvider));
});

final movieDetailsProvider = FutureProvider.family<Movie, int>((ref, tmdbId) {
  return ref.watch(movieRepositoryProvider).getMovieDetails(tmdbId);
});

final movieWatchProvidersProvider = FutureProvider.family<List<WatchProviderOption>, int>(
  (ref, tmdbId) {
    return ref.watch(movieRepositoryProvider).getWatchProviders(tmdbId);
  },
);

/// TMDB-Genreliste für die Filterauswahl (§10).
final movieGenresProvider = FutureProvider<Map<int, String>>((ref) {
  return ref.watch(movieRepositoryProvider).getGenres();
});

/// Bei TMDB tatsächlich verfügbare Streaming-Anbieter für die
/// Plattform-Filter-Auswahl (§10) - keine selbst erfundene Plattformliste.
final watchProviderListProvider = FutureProvider<List<WatchProviderOption>>((ref) {
  return ref.watch(movieRepositoryProvider).getAvailableWatchProviders();
});

/// Trailer für den "Trailer ansehen"-Button (§9) - `null`, wenn TMDB keinen
/// passenden YouTube-Trailer liefert.
final movieTrailerProvider = FutureProvider.family<MovieTrailer?, int>((ref, tmdbId) {
  return ref.watch(movieRepositoryProvider).getTrailer(tmdbId);
});
