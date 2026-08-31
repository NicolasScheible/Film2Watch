import 'dart:math';

import 'package:film2watch/models/movie.dart';
import 'package:film2watch/models/movie_swipe.dart';
import 'package:film2watch/utils/boost.dart';
import 'package:flutter_test/flutter_test.dart';

Movie _movie(int id, {List<int> genreIds = const [], double voteAverage = 0}) => Movie(
      tmdbId: id,
      title: 'Film $id',
      originalTitle: 'Film $id',
      overview: '',
      posterPath: null,
      backdropPath: null,
      releaseDate: null,
      genreIds: genreIds,
      genres: const [],
      voteAverage: voteAverage,
      voteCount: 0,
      runtime: null,
      originalLanguage: 'de',
    );

MovieSwipe _like({required String uid, required int movieId}) {
  final now = DateTime(2024);
  return MovieSwipe(
    uid: uid,
    movieId: movieId,
    decision: SwipeDecision.like,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  group('countFriendLikes', () {
    test('zählt Likes von Freunden pro Film', () {
      final counts = countFriendLikes(
        groupLikes: [
          _like(uid: 'bob', movieId: 1),
          _like(uid: 'carol', movieId: 1),
          _like(uid: 'bob', movieId: 2),
        ],
        friendUids: {'bob', 'carol'},
      );

      expect(counts, {1: 2, 2: 1});
    });

    test('Likes von Nicht-Freunden zählen nicht mit, auch wenn sie Gruppenmitglieder sind', () {
      final counts = countFriendLikes(
        groupLikes: [
          _like(uid: 'bob', movieId: 1),
          _like(uid: 'stranger', movieId: 1),
        ],
        friendUids: {'bob'},
      );

      expect(counts, {1: 1});
    });

    test('ohne Freundes-Likes ist die Zähl-Map leer', () {
      final counts = countFriendLikes(
        groupLikes: [_like(uid: 'stranger', movieId: 1)],
        friendUids: {'bob'},
      );

      expect(counts, isEmpty);
    });

    test('leere Eingaben ergeben eine leere Map (keine Endlosschleife/kein Fehler)', () {
      expect(countFriendLikes(groupLikes: const [], friendUids: const {}), isEmpty);
    });

    test('derselbe Freund liked in dieser Gruppenzählung nie doppelt (ein Like-Dokument pro uid+movie)', () {
      // Firestore erlaubt strukturell nur ein Swipe-Dokument pro (uid,
      // movieId) - diese Funktion muss trotzdem robust bleiben, falls die
      // Eingabeliste (z. B. durch einen Aufrufer-Fehler) ein Duplikat enthält.
      final counts = countFriendLikes(
        groupLikes: [_like(uid: 'bob', movieId: 1), _like(uid: 'bob', movieId: 1)],
        friendUids: {'bob'},
      );
      expect(counts, {1: 2});
    });
  });

  group('sortByFriendLikeBoost', () {
    test('sortiert absteigend nach friend_likes (ORDER BY friend_likes DESC)', () {
      final movies = [_movie(1), _movie(2), _movie(3)];
      final sorted = sortByFriendLikeBoost(
        movies,
        {1: 1, 2: 3, 3: 0},
        random: Random(42),
      );

      expect(sorted.map((m) => m.tmdbId), [2, 1, 3]);
    });

    test('ohne jeglichen Boost bleibt die Menge unverändert, nur die Reihenfolge ist zufällig (RANDOM())', () {
      final movies = [_movie(1), _movie(2), _movie(3), _movie(4)];
      final sorted = sortByFriendLikeBoost(movies, const {}, random: Random(1));

      expect(sorted.map((m) => m.tmdbId).toSet(), {1, 2, 3, 4});
      expect(sorted.length, 4);
    });

    test('ein einzelner Boost-Kandidat wird an die Spitze sortiert', () {
      final movies = [_movie(1), _movie(2), _movie(3)];
      final sorted = sortByFriendLikeBoost(movies, {3: 5}, random: Random(7));

      expect(sorted.first.tmdbId, 3);
    });

    test('mehrere Kandidaten werden korrekt nach absteigender friend_likes-Anzahl sortiert', () {
      final movies = [_movie(1), _movie(2), _movie(3), _movie(4)];
      final sorted = sortByFriendLikeBoost(
        movies,
        {1: 2, 2: 5, 3: 5, 4: 1},
        random: Random(3),
      );

      final likeCounts = {1: 2, 2: 5, 3: 5, 4: 1};
      final sortedCounts = sorted.map((m) => likeCounts[m.tmdbId]).toList();
      expect(sortedCounts, [5, 5, 2, 1]);
    });

    test('erzeugt, dupliziert oder entfernt nie einen Film (reine Umordnung)', () {
      final movies = [_movie(1), _movie(2), _movie(3)];
      final sorted = sortByFriendLikeBoost(movies, {1: 10}, random: Random(9));

      expect(sorted.length, movies.length);
      expect(sorted.map((m) => m.tmdbId).toSet(), movies.map((m) => m.tmdbId).toSet());
    });

    test('leere Filmliste bleibt leer', () {
      expect(sortByFriendLikeBoost(const [], const {}), isEmpty);
    });

    test('derselbe Seed erzeugt eine deterministische Reihenfolge bei Gleichstand (Testbarkeit)', () {
      final movies = [_movie(1), _movie(2), _movie(3)];
      final first = sortByFriendLikeBoost(movies, const {}, random: Random(123));
      final second = sortByFriendLikeBoost(movies, const {}, random: Random(123));

      expect(first.map((m) => m.tmdbId), second.map((m) => m.tmdbId));
    });
  });

  group('computeBoostScore (§7, voller personalisierter Score)', () {
    test('Beispielrechnung aus §7 der Master-Spezifikation: 30 + 40 + 42,5 + 10 = 122,5', () {
      final movie = _movie(1, genreIds: const [27], voteAverage: 8.5);
      final score = computeBoostScore(
        movie: movie,
        friendLikeCounts: {1: 1},
        topGenres: {27},
        dislikedGenres: const {},
        random: 10,
      );

      expect(score, closeTo(122.5, 0.0001));
    });

    test('ohne jedes Signal besteht der Score nur aus Rating und Zufall', () {
      final movie = _movie(1, voteAverage: 6.0);
      final score = computeBoostScore(
        movie: movie,
        friendLikeCounts: const {},
        topGenres: const {},
        dislikedGenres: const {},
        random: 5,
      );

      expect(score, closeTo(6.0 * 5 + 5, 0.0001));
    });

    test('Freundes-Boost ist kumulativ pro Freund (nicht flat pro Film)', () {
      final movie = _movie(1);
      final oneFriend = computeBoostScore(
        movie: movie,
        friendLikeCounts: {1: 1},
        topGenres: const {},
        dislikedGenres: const {},
        random: 0,
      );
      final threeFriends = computeBoostScore(
        movie: movie,
        friendLikeCounts: {1: 3},
        topGenres: const {},
        dislikedGenres: const {},
        random: 0,
      );

      expect(oneFriend, closeTo(40, 0.0001));
      expect(threeFriends, closeTo(120, 0.0001));
    });

    test('Genre-Bonus ist ein flacher Bonus, sobald irgendein Top-Genre getroffen wird', () {
      final oneMatch = computeBoostScore(
        movie: _movie(1, genreIds: const [27, 99]),
        friendLikeCounts: const {},
        topGenres: {27},
        dislikedGenres: const {},
        random: 0,
      );
      final twoMatches = computeBoostScore(
        movie: _movie(2, genreIds: const [27, 28]),
        friendLikeCounts: const {},
        topGenres: {27, 28},
        dislikedGenres: const {},
        random: 0,
      );

      expect(oneMatch, closeTo(30, 0.0001));
      expect(twoMatches, closeTo(30, 0.0001));
    });

    test('kein Genre-Bonus, wenn kein Genre des Films unter den Top-Genres ist', () {
      final score = computeBoostScore(
        movie: _movie(1, genreIds: const [12]),
        friendLikeCounts: const {},
        topGenres: {27},
        dislikedGenres: const {},
        random: 0,
      );
      expect(score, closeTo(0, 0.0001));
    });

    test('Anti-Boost zieht -10 je überschneidendem, bereits gedislikten Genre ab', () {
      final oneOverlap = computeBoostScore(
        movie: _movie(1, genreIds: const [27]),
        friendLikeCounts: const {},
        topGenres: const {},
        dislikedGenres: {27: 5},
        random: 0,
      );
      final twoOverlaps = computeBoostScore(
        movie: _movie(2, genreIds: const [27, 28]),
        friendLikeCounts: const {},
        topGenres: const {},
        dislikedGenres: {27: 1, 28: 1},
        random: 0,
      );

      expect(oneOverlap, closeTo(-10, 0.0001));
      expect(twoOverlaps, closeTo(-20, 0.0001));
    });

    test('Anti-Boost-Zählung des Users beeinflusst nicht die Höhe - nur ob das Genre überhaupt vorkommt', () {
      final score = computeBoostScore(
        movie: _movie(1, genreIds: const [27]),
        friendLikeCounts: const {},
        topGenres: const {},
        dislikedGenres: {27: 500},
        random: 0,
      );
      expect(score, closeTo(-10, 0.0001));
    });

    test('Rating fließt linear mit Faktor 5 ein (Rating x 5)', () {
      final score = computeBoostScore(
        movie: _movie(1, voteAverage: 7.2),
        friendLikeCounts: const {},
        topGenres: const {},
        dislikedGenres: const {},
        random: 0,
      );
      expect(score, closeTo(36.0, 0.0001));
    });

    test('alle Faktoren kombinieren sich additiv', () {
      final score = computeBoostScore(
        movie: _movie(1, genreIds: const [27], voteAverage: 5.0),
        friendLikeCounts: {1: 2},
        topGenres: {27},
        dislikedGenres: {28: 1},
        random: 3,
      );
      // 2*40 (Freunde) + 30 (Genre) + 0 (kein Anti-Boost, Genre 28 nicht im Film) + 25 (Rating) + 3 (Zufall)
      expect(score, closeTo(80 + 30 + 25 + 3, 0.0001));
    });
  });

  group('sortByBoostScore', () {
    test('sortiert absteigend nach dem vollen Boost-Score', () {
      final movies = [
        _movie(1, voteAverage: 2.0),
        _movie(2, genreIds: const [27], voteAverage: 2.0),
        _movie(3, voteAverage: 2.0),
      ];
      final sorted = sortByBoostScore(
        movies,
        friendLikeCounts: const {},
        topGenres: {27},
        dislikedGenres: const {},
        random: Random(1),
      );

      expect(sorted.first.tmdbId, 2);
    });

    test('erzeugt, dupliziert oder entfernt nie einen Film (reine Umordnung)', () {
      final movies = [_movie(1), _movie(2), _movie(3)];
      final sorted = sortByBoostScore(
        movies,
        friendLikeCounts: {1: 5},
        topGenres: const {},
        dislikedGenres: const {},
        random: Random(9),
      );

      expect(sorted.length, movies.length);
      expect(sorted.map((m) => m.tmdbId).toSet(), movies.map((m) => m.tmdbId).toSet());
    });

    test('leere Filmliste bleibt leer', () {
      expect(
        sortByBoostScore(const [], friendLikeCounts: const {}, topGenres: const {}, dislikedGenres: const {}),
        isEmpty,
      );
    });

    test('derselbe Seed erzeugt eine deterministische Reihenfolge (Testbarkeit)', () {
      final movies = [_movie(1), _movie(2), _movie(3), _movie(4)];
      final first = sortByBoostScore(
        movies,
        friendLikeCounts: const {},
        topGenres: const {},
        dislikedGenres: const {},
        random: Random(55),
      );
      final second = sortByBoostScore(
        movies,
        friendLikeCounts: const {},
        topGenres: const {},
        dislikedGenres: const {},
        random: Random(55),
      );

      expect(first.map((m) => m.tmdbId), second.map((m) => m.tmdbId));
    });

    test('ein starker Anti-Boost drückt einen Film zuverlässig unter unbeeinflusste Filme', () {
      // Drei überschneidende, bereits gedislikte Genres -> Score liegt immer
      // im Bereich [-30, -10) (Zufallsanteil 0-20 exklusiv); der unbeeinflusste
      // Film liegt immer im Bereich [0, 20) - unabhängig vom RNG-Seed ist der
      // erste Film also garantiert niedriger.
      final movies = [
        _movie(1, genreIds: const [1, 2, 3], voteAverage: 0),
        _movie(2, voteAverage: 0),
      ];
      final sorted = sortByBoostScore(
        movies,
        friendLikeCounts: const {},
        topGenres: const {},
        dislikedGenres: {1: 1, 2: 1, 3: 1},
        random: Random(2),
      );

      expect(sorted.first.tmdbId, 2);
    });
  });
}
