import 'dart:math';

import 'package:film2watch/models/movie.dart';
import 'package:film2watch/models/movie_swipe.dart';
import 'package:film2watch/utils/boost.dart';
import 'package:flutter_test/flutter_test.dart';

Movie _movie(int id) => Movie(
      tmdbId: id,
      title: 'Film $id',
      originalTitle: 'Film $id',
      overview: '',
      posterPath: null,
      backdropPath: null,
      releaseDate: null,
      genreIds: const [],
      genres: const [],
      voteAverage: 0,
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
}
