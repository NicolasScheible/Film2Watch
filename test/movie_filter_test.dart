import 'dart:convert';

import 'package:film2watch/models/movie_filter.dart';
import 'package:film2watch/repositories/movie_repository.dart';
import 'package:film2watch/services/tmdb_service.dart';
import 'package:film2watch/utils/tmdb_exceptions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> _movieJson(int id) => {
      'id': id,
      'title': 'Film $id',
      'genre_ids': <dynamic>[],
    };

void main() {
  group('MovieFilter', () {
    test('isActive/activeCount sind false/0, wenn kein Kriterium gesetzt ist', () {
      expect(MovieFilter.empty.isActive, isFalse);
      expect(MovieFilter.empty.activeCount, 0);
    });

    test('isActive wird true, sobald ein einzelnes Kriterium gesetzt ist', () {
      expect(const MovieFilter(watchProviderId: 8).isActive, isTrue);
      expect(const MovieFilter(genreIds: {28}).isActive, isTrue);
      expect(const MovieFilter(yearFrom: 2000).isActive, isTrue);
      expect(const MovieFilter(minRating: 6).isActive, isTrue);
      expect(const MovieFilter(runtimeFromMinutes: 60).isActive, isTrue);
    });

    test('minRating von genau 0 zählt nicht als aktiver Filter', () {
      expect(const MovieFilter(minRating: 0).isActive, isFalse);
    });

    test('activeCount zählt pro Kriterien-Gruppe, nicht pro Einzelwert', () {
      final filter = const MovieFilter(yearFrom: 2000, yearTo: 2020, runtimeFromMinutes: 60, runtimeToMinutes: 120);
      expect(filter.activeCount, 2);
    });

    test('copyWith mit clear-Flag setzt das jeweilige Feld zurück', () {
      final filter = const MovieFilter(watchProviderId: 8, minRating: 7);
      final cleared = filter.copyWith(clearWatchProviderId: true, clearMinRating: true);
      expect(cleared.watchProviderId, isNull);
      expect(cleared.minRating, isNull);
    });

    test('zwei MovieFilter mit denselben Werten sind gleich (für Provider-Vergleich)', () {
      const a = MovieFilter(watchProviderId: 8, genreIds: {28, 12});
      const b = MovieFilter(watchProviderId: 8, genreIds: {12, 28});
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });

  group('TmdbService.discoverMovies mit Filtern', () {
    late Uri capturedUri;

    TmdbService serviceCapturing() {
      final client = MockClient((request) async {
        capturedUri = request.url;
        return http.Response(
          jsonEncode({'page': 1, 'total_pages': 1, 'total_results': 0, 'results': <dynamic>[]}),
          200,
        );
      });
      return TmdbService(client, accessToken: 'test-token');
    }

    test('ohne Filter werden keine Filter-Parameter gesendet', () async {
      await serviceCapturing().discoverMovies(page: 1);
      expect(capturedUri.queryParameters.containsKey('with_watch_providers'), isFalse);
      expect(capturedUri.queryParameters.containsKey('with_genres'), isFalse);
      expect(capturedUri.queryParameters.containsKey('primary_release_date.gte'), isFalse);
      expect(capturedUri.queryParameters.containsKey('vote_average.gte'), isFalse);
      expect(capturedUri.queryParameters.containsKey('with_runtime.gte'), isFalse);
    });

    test('watchProviderId wird korrekt inkl. watch_region und flatrate-Typ übergeben', () async {
      await serviceCapturing().discoverMovies(page: 1, watchProviderId: 8, region: 'DE');
      expect(capturedUri.queryParameters['with_watch_providers'], '8');
      expect(capturedUri.queryParameters['watch_region'], 'DE');
      expect(capturedUri.queryParameters['with_watch_monetization_types'], 'flatrate');
    });

    test('mehrere genreIds werden mit Pipe (ODER) verknüpft', () async {
      await serviceCapturing().discoverMovies(page: 1, genreIds: {28, 12});
      final value = capturedUri.queryParameters['with_genres']!;
      expect(value.split('|').toSet(), {'28', '12'});
    });

    test('yearFrom/yearTo werden als vollständige Datumsgrenzen übergeben', () async {
      await serviceCapturing().discoverMovies(page: 1, yearFrom: 2000, yearTo: 2020);
      expect(capturedUri.queryParameters['primary_release_date.gte'], '2000-01-01');
      expect(capturedUri.queryParameters['primary_release_date.lte'], '2020-12-31');
    });

    test('minRating von 0 wird nicht als Filter übergeben', () async {
      await serviceCapturing().discoverMovies(page: 1, minRating: 0);
      expect(capturedUri.queryParameters.containsKey('vote_average.gte'), isFalse);
    });

    test('minRating größer 0 wird übergeben', () async {
      await serviceCapturing().discoverMovies(page: 1, minRating: 6.5);
      expect(capturedUri.queryParameters['vote_average.gte'], '6.5');
    });

    test('Laufzeit-Grenzen werden übergeben', () async {
      await serviceCapturing().discoverMovies(page: 1, runtimeFromMinutes: 60, runtimeToMinutes: 150);
      expect(capturedUri.queryParameters['with_runtime.gte'], '60');
      expect(capturedUri.queryParameters['with_runtime.lte'], '150');
    });

    test('alle Filter gleichzeitig werden kombiniert übergeben', () async {
      await serviceCapturing().discoverMovies(
        page: 1,
        watchProviderId: 8,
        genreIds: {28},
        yearFrom: 2000,
        yearTo: 2020,
        minRating: 5,
        runtimeFromMinutes: 60,
        runtimeToMinutes: 150,
      );
      expect(capturedUri.queryParameters['with_watch_providers'], '8');
      expect(capturedUri.queryParameters['with_genres'], '28');
      expect(capturedUri.queryParameters['primary_release_date.gte'], '2000-01-01');
      expect(capturedUri.queryParameters['vote_average.gte'], '5.0');
      expect(capturedUri.queryParameters['with_runtime.gte'], '60');
    });
  });

  group('MovieRepository mit MovieFilter', () {
    test('discoverMovies reicht den Filter an TmdbService/TMDB durch', () async {
      late Uri capturedUri;
      final client = MockClient((request) async {
        if (request.url.path.contains('/discover/movie')) {
          capturedUri = request.url;
          return http.Response(
            jsonEncode({
              'page': 1,
              'total_pages': 1,
              'total_results': 1,
              'results': [_movieJson(1)],
            }),
            200,
          );
        }
        if (request.url.path.contains('/genre/movie/list')) {
          return http.Response(jsonEncode({'genres': <dynamic>[]}), 200);
        }
        return http.Response('{}', 404);
      });
      final repository = MovieRepository(TmdbService(client, accessToken: 'test-token'));

      await repository.discoverMovies(filter: const MovieFilter(watchProviderId: 9));

      expect(capturedUri.queryParameters['with_watch_providers'], '9');
    });

    test('getAvailableWatchProviders liefert echte TMDB-Anbieter sortiert nach Namen', () async {
      final client = MockClient((request) async {
        if (request.url.path.contains('/watch/providers/movie')) {
          return http.Response(
            jsonEncode({
              'results': [
                {'provider_id': 8, 'provider_name': 'Netflix', 'logo_path': '/n.jpg'},
                {'provider_id': 9, 'provider_name': 'Amazon Prime Video', 'logo_path': '/a.jpg'},
              ],
            }),
            200,
          );
        }
        return http.Response('{}', 404);
      });
      final repository = MovieRepository(TmdbService(client, accessToken: 'test-token'));

      final providers = await repository.getAvailableWatchProviders();

      expect(providers.map((p) => p.providerName), ['Amazon Prime Video', 'Netflix']);
    });

    test('getAvailableWatchProviders wird nur einmal von TMDB geladen (Cache)', () async {
      var requestCount = 0;
      final client = MockClient((request) async {
        requestCount++;
        return http.Response(jsonEncode({'results': <dynamic>[]}), 200);
      });
      final repository = MovieRepository(TmdbService(client, accessToken: 'test-token'));

      await repository.getAvailableWatchProviders();
      await repository.getAvailableWatchProviders();

      expect(requestCount, 1);
    });

    test('getGenres liefert die TMDB-Genreliste als id->name-Map', () async {
      final client = MockClient((request) async {
        if (request.url.path.contains('/genre/movie/list')) {
          return http.Response(
            jsonEncode({
              'genres': [
                {'id': 28, 'name': 'Action'},
                {'id': 12, 'name': 'Abenteuer'},
              ],
            }),
            200,
          );
        }
        return http.Response('{}', 404);
      });
      final repository = MovieRepository(TmdbService(client, accessToken: 'test-token'));

      final genres = await repository.getGenres();

      expect(genres, {28: 'Action', 12: 'Abenteuer'});
    });

    test('TMDB-Fehler beim Laden der Watch-Provider-Liste wird durchgereicht', () async {
      final client = MockClient((request) async => http.Response('{}', 500));
      final repository = MovieRepository(TmdbService(client, accessToken: 'test-token'));

      expect(
        () => repository.getAvailableWatchProviders(),
        throwsA(isA<TmdbServerException>()),
      );
    });
  });
}
