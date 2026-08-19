import 'dart:convert';

import 'package:film2watch/models/movie.dart';
import 'package:film2watch/repositories/movie_repository.dart';
import 'package:film2watch/services/tmdb_image_service.dart';
import 'package:film2watch/services/tmdb_service.dart';
import 'package:film2watch/utils/movie_list_utils.dart';
import 'package:film2watch/utils/tmdb_exceptions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> _fullMovieJson({int id = 550, String title = 'Fight Club'}) {
  return {
    'id': id,
    'title': title,
    'original_title': title,
    'overview': 'Ein Insomniac-Büroangestellter ...',
    'poster_path': '/poster.jpg',
    'backdrop_path': '/backdrop.jpg',
    'release_date': '1999-10-15',
    'genre_ids': [18, 53],
    'genres': [
      {'id': 18, 'name': 'Drama'},
      {'id': 53, 'name': 'Thriller'},
    ],
    'vote_average': 8.4,
    'vote_count': 26280,
    'runtime': 139,
    'original_language': 'en',
  };
}

void main() {
  group('Movie.fromTmdbJson', () {
    test('mappt ein vollständiges TMDB-JSON korrekt', () {
      final movie = Movie.fromTmdbJson(_fullMovieJson());

      expect(movie.tmdbId, 550);
      expect(movie.title, 'Fight Club');
      expect(movie.overview, contains('Insomniac'));
      expect(movie.voteAverage, 8.4);
      expect(movie.voteCount, 26280);
      expect(movie.runtime, 139);
      expect(movie.originalLanguage, 'en');
    });

    test('kommt mit fehlenden optionalen Feldern klar, ohne abzustürzen', () {
      final movie = Movie.fromTmdbJson({'id': 42, 'title': 'Minimal Movie'});

      expect(movie.tmdbId, 42);
      expect(movie.title, 'Minimal Movie');
      expect(movie.overview, '');
      expect(movie.posterPath, isNull);
      expect(movie.backdropPath, isNull);
      expect(movie.releaseDate, isNull);
      expect(movie.genreIds, isEmpty);
      expect(movie.genres, isEmpty);
      expect(movie.voteAverage, 0.0);
      expect(movie.voteCount, 0);
      expect(movie.runtime, isNull);
    });

    test('wirft eine TmdbInvalidResponseException ohne gültige ID', () {
      expect(
        () => Movie.fromTmdbJson({'title': 'Ohne ID'}),
        throwsA(isA<TmdbInvalidResponseException>()),
      );
    });

    test('parst das Erscheinungsdatum korrekt', () {
      final movie = Movie.fromTmdbJson(_fullMovieJson());
      expect(movie.releaseDate, DateTime(1999, 10, 15));
    });

    test('behandelt ein leeres/ungültiges Datum robust statt abzustürzen', () {
      final json = _fullMovieJson()..['release_date'] = '';
      final movie = Movie.fromTmdbJson(json);
      expect(movie.releaseDate, isNull);
    });

    test('löst genre_ids über die genreNames-Map auf, wenn keine genres vorliegen', () {
      final json = {'id': 1, 'title': 'Genre Test', 'genre_ids': [28, 12]};
      final movie = Movie.fromTmdbJson(json, genreNames: {28: 'Action', 12: 'Abenteuer'});
      expect(movie.genres, ['Action', 'Abenteuer']);
    });

    test('bevorzugt vollständige genres-Objekte gegenüber genreNames', () {
      final movie = Movie.fromTmdbJson(_fullMovieJson(), genreNames: {18: 'Falsch'});
      expect(movie.genres, ['Drama', 'Thriller']);
    });
  });

  group('TmdbImageService', () {
    test('baut eine Poster-URL aus dem TMDB-Pfad', () {
      expect(
        TmdbImageService.posterUrl('/poster.jpg'),
        'https://image.tmdb.org/t/p/w500/poster.jpg',
      );
    });

    test('gibt null zurück, wenn kein Poster-Pfad vorhanden ist', () {
      expect(TmdbImageService.posterUrl(null), isNull);
    });

    test('baut eine Backdrop-URL aus dem TMDB-Pfad', () {
      expect(
        TmdbImageService.backdropUrl('/backdrop.jpg'),
        'https://image.tmdb.org/t/p/w1280/backdrop.jpg',
      );
    });
  });

  group('mergeUniqueMovies', () {
    test('vermeidet Duplikate anhand der tmdbId', () {
      final page1 = [Movie.fromTmdbJson(_fullMovieJson(id: 1)), Movie.fromTmdbJson(_fullMovieJson(id: 2))];
      final page2 = [Movie.fromTmdbJson(_fullMovieJson(id: 2)), Movie.fromTmdbJson(_fullMovieJson(id: 3))];

      final merged = mergeUniqueMovies(page1, page2);

      expect(merged.map((m) => m.tmdbId), [1, 2, 3]);
    });
  });

  group('TmdbService Fehlerbehandlung (HTTP gemockt, keine echten Requests)', () {
    TmdbService serviceReturning(int statusCode, {String body = '{}'}) {
      final client = MockClient((request) async => http.Response(body, statusCode));
      return TmdbService(client, accessToken: 'test-token');
    }

    test('wirft TmdbNotConfiguredException ohne Access Token', () {
      final client = MockClient((request) async => http.Response('{}', 200));
      final service = TmdbService(client, accessToken: '');

      expect(
        () => service.movieDetails(1),
        throwsA(isA<TmdbNotConfiguredException>()),
      );
    });

    test('HTTP 401 wirft TmdbUnauthorizedException', () {
      expect(
        () => serviceReturning(401).movieDetails(1),
        throwsA(isA<TmdbUnauthorizedException>()),
      );
    });

    test('HTTP 404 wirft TmdbNotFoundException', () {
      expect(
        () => serviceReturning(404).movieDetails(1),
        throwsA(isA<TmdbNotFoundException>()),
      );
    });

    test('HTTP 429 wirft TmdbRateLimitException', () {
      expect(
        () => serviceReturning(429).movieDetails(1),
        throwsA(isA<TmdbRateLimitException>()),
      );
    });

    test('HTTP 500 wirft TmdbServerException', () {
      expect(
        () => serviceReturning(500).movieDetails(1),
        throwsA(isA<TmdbServerException>()),
      );
    });

    test('ungültiges JSON wirft TmdbInvalidResponseException', () {
      expect(
        () => serviceReturning(200, body: 'not json').movieDetails(1),
        throwsA(isA<TmdbInvalidResponseException>()),
      );
    });
  });

  group('MovieRepository', () {
    MovieRepository repositoryReturning(Map<String, http.Response Function(http.Request)> responsesByPathContains) {
      final client = MockClient((request) async {
        for (final entry in responsesByPathContains.entries) {
          if (request.url.path.contains(entry.key)) return entry.value(request);
        }
        return http.Response('{}', 404);
      });
      return MovieRepository(TmdbService(client, accessToken: 'test-token'));
    }

    test('Movie Search liefert echte gemappte Filme zurück', () async {
      final repository = repositoryReturning({
        '/search/movie': (request) => http.Response(
              jsonEncode({
                'page': 1,
                'total_pages': 3,
                'total_results': 3,
                'results': [_fullMovieJson()],
              }),
              200,
            ),
        '/genre/movie/list': (request) =>
            http.Response(jsonEncode({'genres': []}), 200),
      });

      final page = await repository.searchMovies(query: 'Fight Club');

      expect(page.movies, hasLength(1));
      expect(page.movies.single.title, 'Fight Club');
    });

    test('eine leere Suchanfrage löst keinen Request aus', () async {
      final repository = repositoryReturning({});
      final page = await repository.searchMovies(query: '   ');
      expect(page.movies, isEmpty);
    });

    test('Movie Details werden korrekt gemappt', () async {
      final repository = repositoryReturning({
        '/movie/550': (request) => http.Response(jsonEncode(_fullMovieJson()), 200),
      });

      final movie = await repository.getMovieDetails(550);

      expect(movie.tmdbId, 550);
      expect(movie.runtime, 139);
    });

    test('Pagination: page/totalPages/hasNextPage werden korrekt gemappt', () async {
      final repository = repositoryReturning({
        '/discover/movie': (request) => http.Response(
              jsonEncode({
                'page': 2,
                'total_pages': 5,
                'total_results': 100,
                'results': [_fullMovieJson(id: 2)],
              }),
              200,
            ),
        '/genre/movie/list': (request) =>
            http.Response(jsonEncode({'genres': []}), 200),
      });

      final page = await repository.discoverMovies(page: 2);

      expect(page.page, 2);
      expect(page.totalPages, 5);
      expect(page.hasNextPage, isTrue);
    });

    test('defekte einzelne Ergebnis-Einträge werfen die restliche Seite nicht weg', () async {
      final repository = repositoryReturning({
        '/discover/movie': (request) => http.Response(
              jsonEncode({
                'page': 1,
                'total_pages': 1,
                'total_results': 2,
                'results': [
                  {'title': 'Ohne ID - defekt'},
                  _fullMovieJson(id: 7),
                ],
              }),
              200,
            ),
        '/genre/movie/list': (request) =>
            http.Response(jsonEncode({'genres': []}), 200),
      });

      final page = await repository.discoverMovies();

      expect(page.movies, hasLength(1));
      expect(page.movies.single.tmdbId, 7);
    });
  });
}
