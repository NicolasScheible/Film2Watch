import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:film2watch/models/movie_cast.dart';
import 'package:film2watch/repositories/movie_repository.dart';
import 'package:film2watch/services/tmdb_service.dart';
import 'package:film2watch/utils/tmdb_exceptions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> _castMember({required int id, required int order, String name = 'Star'}) {
  return {'id': id, 'order': order, 'name': name};
}

void main() {
  group('selectMainCastIds (§7 Cast-Anti-Boost: "gleicher Hauptdarsteller")', () {
    test('mappt eine gültige Credits-Antwort korrekt auf Personen-IDs', () {
      final json = {
        'cast': [_castMember(id: 100, order: 0), _castMember(id: 200, order: 1)],
      };
      expect(selectMainCastIds(json), [100, 200]);
    });

    test('verwendet die Top-3-Cast-Einträge nach order (mit dem Produktverantwortlichen abgestimmt)', () {
      final json = {
        'cast': [
          _castMember(id: 400, order: 3),
          _castMember(id: 100, order: 0),
          _castMember(id: 300, order: 2),
          _castMember(id: 200, order: 1),
          _castMember(id: 500, order: 4),
        ],
      };
      expect(selectMainCastIds(json), [100, 200, 300]);
    });

    test('sortiert robust nach order, auch wenn TMDB die Liste unsortiert liefern würde', () {
      final json = {
        'cast': [_castMember(id: 200, order: 1), _castMember(id: 100, order: 0)],
      };
      expect(selectMainCastIds(json), [100, 200]);
    });

    test('fehlendes "cast"-Array degradiert sauber zu einer leeren Liste (kein Fehler)', () {
      expect(selectMainCastIds({}), isEmpty);
      expect(selectMainCastIds({'cast': 'invalid'}), isEmpty);
    });

    test('Cast-Einträge ohne gültige id/order werden ignoriert, statt die ganze Liste zu verwerfen', () {
      final json = {
        'cast': [
          {'order': 0, 'name': 'Ohne ID'},
          {'id': 100, 'name': 'Ohne Order'},
          _castMember(id: 200, order: 0),
        ],
      };
      expect(selectMainCastIds(json), [200]);
    });

    test('ein eigener limit-Wert überschreibt die Standard-Top-3', () {
      final json = {
        'cast': [
          _castMember(id: 100, order: 0),
          _castMember(id: 200, order: 1),
          _castMember(id: 300, order: 2),
        ],
      };
      expect(selectMainCastIds(json, limit: 1), [100]);
    });
  });

  group('MovieRepository.getMainCastIds', () {
    test('lädt und mappt die Top-3-Cast-IDs über /movie/{id}/credits', () async {
      final client = MockClient((request) async {
        if (request.url.path.contains('/movie/550/credits')) {
          return http.Response(
            jsonEncode({
              'cast': [_castMember(id: 11, order: 0), _castMember(id: 22, order: 1)],
            }),
            200,
          );
        }
        return http.Response('{}', 404);
      });
      final repository = MovieRepository(TmdbService(client, accessToken: 'test-token'));

      final castIds = await repository.getMainCastIds(550);

      expect(castIds, [11, 22]);
    });

    test('gibt eine leere Liste zurück, wenn TMDB keine Besetzung liefert (kein Fehler)', () async {
      final client = MockClient((request) async => http.Response(jsonEncode({'cast': <dynamic>[]}), 200));
      final repository = MovieRepository(TmdbService(client, accessToken: 'test-token'));

      expect(await repository.getMainCastIds(550), isEmpty);
    });

    test('cached das Ergebnis - kein wiederholter Request für denselben Film', () async {
      var requestCount = 0;
      final client = MockClient((request) async {
        requestCount++;
        return http.Response(jsonEncode({'cast': <dynamic>[]}), 200);
      });
      final repository = MovieRepository(TmdbService(client, accessToken: 'test-token'));

      await repository.getMainCastIds(550);
      await repository.getMainCastIds(550);

      expect(requestCount, 1);
    });

    test('HTTP-Fehler wird durchgereicht statt verschluckt', () async {
      final client = MockClient((request) async => http.Response('{}', 500));
      final repository = MovieRepository(TmdbService(client, accessToken: 'test-token'));

      expect(() => repository.getMainCastIds(550), throwsA(isA<TmdbServerException>()));
    });

    test('HTTP 401/404/429 werden jeweils als passende TmdbException durchgereicht', () async {
      final unauthorized = MovieRepository(
        TmdbService(MockClient((r) async => http.Response('{}', 401)), accessToken: 'test-token'),
      );
      final notFound = MovieRepository(
        TmdbService(MockClient((r) async => http.Response('{}', 404)), accessToken: 'test-token'),
      );
      final rateLimited = MovieRepository(
        TmdbService(MockClient((r) async => http.Response('{}', 429)), accessToken: 'test-token'),
      );

      await expectLater(unauthorized.getMainCastIds(1), throwsA(isA<TmdbUnauthorizedException>()));
      await expectLater(notFound.getMainCastIds(2), throwsA(isA<TmdbNotFoundException>()));
      await expectLater(rateLimited.getMainCastIds(3), throwsA(isA<TmdbRateLimitException>()));
    });

    test('ungültiges JSON wird als TmdbInvalidResponseException durchgereicht', () async {
      final client = MockClient((request) async => http.Response('not json', 200));
      final repository = MovieRepository(TmdbService(client, accessToken: 'test-token'));

      expect(() => repository.getMainCastIds(550), throwsA(isA<TmdbInvalidResponseException>()));
    });

    test('kein Internet (SocketException) wird als TmdbNetworkException durchgereicht', () async {
      final client = MockClient((request) async => throw const SocketException('Keine Verbindung'));
      final repository = MovieRepository(TmdbService(client, accessToken: 'test-token'));

      expect(() => repository.getMainCastIds(550), throwsA(isA<TmdbNetworkException>()));
    });

    test('eine Zeitüberschreitung wird als TmdbNetworkException durchgereicht', () async {
      final client = MockClient((request) async => throw TimeoutException('Zeitüberschreitung'));
      final repository = MovieRepository(TmdbService(client, accessToken: 'test-token'));

      expect(() => repository.getMainCastIds(550), throwsA(isA<TmdbNetworkException>()));
    });
  });

  group('TmdbService.movieCredits', () {
    test('ruft den korrekten Endpunkt auf', () async {
      late Uri capturedUri;
      final client = MockClient((request) async {
        capturedUri = request.url;
        return http.Response(jsonEncode({'cast': <dynamic>[]}), 200);
      });
      final service = TmdbService(client, accessToken: 'test-token');

      await service.movieCredits(550);

      expect(capturedUri.path, '/3/movie/550/credits');
    });
  });
}
