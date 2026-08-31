import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:film2watch/models/movie_trailer.dart';
import 'package:film2watch/repositories/movie_repository.dart';
import 'package:film2watch/services/tmdb_service.dart';
import 'package:film2watch/utils/tmdb_exceptions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> _video({
  required String key,
  String site = 'YouTube',
  String type = 'Trailer',
  bool official = true,
  String? publishedAt,
  String name = 'Official Trailer',
}) {
  return {
    'key': key,
    'site': site,
    'type': type,
    'official': official,
    'published_at': publishedAt,
    'name': name,
  };
}

void main() {
  group('MovieTrailer.selectFromTmdbJson', () {
    test('wählt einen einzelnen YouTube-Trailer aus', () {
      final json = {
        'results': [_video(key: 'abc123')],
      };
      final trailer = MovieTrailer.selectFromTmdbJson(json);
      expect(trailer, isNotNull);
      expect(trailer!.youtubeKey, 'abc123');
      expect(trailer.name, 'Official Trailer');
    });

    test('gibt null zurück, wenn keine Videos vorhanden sind', () {
      expect(MovieTrailer.selectFromTmdbJson({'results': <dynamic>[]}), isNull);
    });

    test('gibt null zurück, wenn "results" fehlt oder ungültig ist', () {
      expect(MovieTrailer.selectFromTmdbJson({}), isNull);
      expect(MovieTrailer.selectFromTmdbJson({'results': 'invalid'}), isNull);
    });

    test('ignoriert Nicht-YouTube-Plattformen (z. B. Vimeo)', () {
      final json = {
        'results': [_video(key: 'vimeo1', site: 'Vimeo')],
      };
      expect(MovieTrailer.selectFromTmdbJson(json), isNull);
    });

    test('ignoriert Nicht-Trailer-Typen (Teaser, Clip, Featurette)', () {
      final json = {
        'results': [
          _video(key: 'teaser1', type: 'Teaser'),
          _video(key: 'clip1', type: 'Clip'),
          _video(key: 'feat1', type: 'Featurette'),
        ],
      };
      expect(MovieTrailer.selectFromTmdbJson(json), isNull);
    });

    test('bevorzugt bei mehreren Trailern den offiziellen', () {
      final json = {
        'results': [
          _video(key: 'inoffiziell', official: false, publishedAt: '2020-01-01T00:00:00Z'),
          _video(key: 'offiziell', official: true, publishedAt: '2019-01-01T00:00:00Z'),
        ],
      };
      final trailer = MovieTrailer.selectFromTmdbJson(json);
      expect(trailer!.youtubeKey, 'offiziell');
    });

    test('bevorzugt bei mehreren offiziellen Trailern den zuletzt veröffentlichten', () {
      final json = {
        'results': [
          _video(key: 'aelter', official: true, publishedAt: '2019-01-01T00:00:00Z'),
          _video(key: 'neuer', official: true, publishedAt: '2021-01-01T00:00:00Z'),
        ],
      };
      final trailer = MovieTrailer.selectFromTmdbJson(json);
      expect(trailer!.youtubeKey, 'neuer');
    });

    test('Video ohne key wird ignoriert', () {
      final json = {
        'results': [
          {'site': 'YouTube', 'type': 'Trailer', 'key': '', 'official': true},
        ],
      };
      expect(MovieTrailer.selectFromTmdbJson(json), isNull);
    });

    test('fehlender Name fällt auf "Trailer" zurück', () {
      final json = {
        'results': [
          {'key': 'xyz', 'site': 'YouTube', 'type': 'Trailer', 'official': true},
        ],
      };
      final trailer = MovieTrailer.selectFromTmdbJson(json);
      expect(trailer!.name, 'Trailer');
    });
  });

  group('MovieRepository.getTrailer', () {
    test('lädt und mappt den Trailer über /movie/{id}/videos', () async {
      final client = MockClient((request) async {
        if (request.url.path.contains('/movie/550/videos')) {
          return http.Response(
            jsonEncode({
              'results': [_video(key: 'abc123')],
            }),
            200,
          );
        }
        return http.Response('{}', 404);
      });
      final repository = MovieRepository(TmdbService(client, accessToken: 'test-token'));

      final trailer = await repository.getTrailer(550);

      expect(trailer, isNotNull);
      expect(trailer!.youtubeKey, 'abc123');
    });

    test('gibt null zurück, wenn TMDB keinen Trailer liefert (kein Fehler)', () async {
      final client = MockClient((request) async {
        return http.Response(jsonEncode({'results': <dynamic>[]}), 200);
      });
      final repository = MovieRepository(TmdbService(client, accessToken: 'test-token'));

      final trailer = await repository.getTrailer(550);

      expect(trailer, isNull);
    });

    test('cached das Ergebnis, auch wenn kein Trailer gefunden wurde (kein wiederholter Request)', () async {
      var requestCount = 0;
      final client = MockClient((request) async {
        requestCount++;
        return http.Response(jsonEncode({'results': <dynamic>[]}), 200);
      });
      final repository = MovieRepository(TmdbService(client, accessToken: 'test-token'));

      await repository.getTrailer(550);
      await repository.getTrailer(550);

      expect(requestCount, 1);
    });

    test('HTTP-Fehler wird durchgereicht statt verschluckt', () async {
      final client = MockClient((request) async => http.Response('{}', 500));
      final repository = MovieRepository(TmdbService(client, accessToken: 'test-token'));

      expect(() => repository.getTrailer(550), throwsA(isA<TmdbServerException>()));
    });

    test('ungültiges JSON wird als TmdbInvalidResponseException durchgereicht', () async {
      final client = MockClient((request) async => http.Response('not json', 200));
      final repository = MovieRepository(TmdbService(client, accessToken: 'test-token'));

      expect(() => repository.getTrailer(550), throwsA(isA<TmdbInvalidResponseException>()));
    });

    test('kein Internet (SocketException) wird als TmdbNetworkException durchgereicht', () async {
      final client = MockClient((request) async => throw const SocketException('Keine Verbindung'));
      final repository = MovieRepository(TmdbService(client, accessToken: 'test-token'));

      expect(() => repository.getTrailer(550), throwsA(isA<TmdbNetworkException>()));
    });

    test('eine Zeitüberschreitung wird als TmdbNetworkException durchgereicht', () async {
      final client = MockClient((request) async => throw TimeoutException('Zeitüberschreitung'));
      final repository = MovieRepository(TmdbService(client, accessToken: 'test-token'));

      expect(() => repository.getTrailer(550), throwsA(isA<TmdbNetworkException>()));
    });
  });

  group('TmdbService.movieVideos', () {
    test('ruft den korrekten Endpunkt mit Sprachparameter auf', () async {
      late Uri capturedUri;
      final client = MockClient((request) async {
        capturedUri = request.url;
        return http.Response(jsonEncode({'results': <dynamic>[]}), 200);
      });
      final service = TmdbService(client, accessToken: 'test-token');

      await service.movieVideos(550, language: 'de-DE');

      expect(capturedUri.path, '/3/movie/550/videos');
      expect(capturedUri.queryParameters['language'], 'de-DE');
    });
  });
}
