import 'package:film2watch/models/movie_swipe.dart';
import 'package:film2watch/models/user_genre_preferences.dart';
import 'package:film2watch/models/user_statistics.dart';
import 'package:flutter_test/flutter_test.dart';

MovieSwipe _swipe(SwipeDecision decision) {
  final now = DateTime(2026, 1, 1);
  return MovieSwipe(uid: 'alice', movieId: 1, decision: decision, createdAt: now, updatedAt: now);
}

void main() {
  group('UserStatistics.fromSwipes (§15: Detaillierte Statistiken)', () {
    test('empty ist der neutrale Ausgangszustand ohne jede Aktivität', () {
      expect(UserStatistics.empty.swipeCount, 0);
      expect(UserStatistics.empty.likeCount, 0);
      expect(UserStatistics.empty.dislikeCount, 0);
      expect(UserStatistics.empty.watchlistCount, 0);
      expect(UserStatistics.empty.matchCount, 0);
      expect(UserStatistics.empty.genrePreferences, UserGenrePreferences.empty);
    });

    test('zählt Likes/Dislikes/Watchlist getrennt und die Gesamtzahl unabhängig vom Typ', () {
      final swipes = [
        _swipe(SwipeDecision.like),
        _swipe(SwipeDecision.like),
        _swipe(SwipeDecision.dislike),
        _swipe(SwipeDecision.watchlist),
        _swipe(SwipeDecision.skip),
        _swipe(SwipeDecision.superSwipe),
      ];

      final statistics = UserStatistics.fromSwipes(
        swipes: swipes,
        matchCount: 0,
        genrePreferences: UserGenrePreferences.empty,
      );

      expect(statistics.swipeCount, 6, reason: 'zählt ALLE Swipes, auch Skip/Super Swipe');
      expect(statistics.likeCount, 2);
      expect(statistics.dislikeCount, 1);
      expect(statistics.watchlistCount, 1);
    });

    test('Skip und Super Swipe fließen nicht in Like/Dislike/Watchlist ein', () {
      final statistics = UserStatistics.fromSwipes(
        swipes: [_swipe(SwipeDecision.skip), _swipe(SwipeDecision.superSwipe)],
        matchCount: 0,
        genrePreferences: UserGenrePreferences.empty,
      );

      expect(statistics.likeCount, 0);
      expect(statistics.dislikeCount, 0);
      expect(statistics.watchlistCount, 0);
      expect(statistics.swipeCount, 2);
    });

    test('übernimmt matchCount und genrePreferences unverändert', () {
      const preferences = UserGenrePreferences(
        genreAffinity: {28: 5.0},
        dislikedGenres: {},
        topGenres: {28},
        dislikedCastIds: {},
      );

      final statistics = UserStatistics.fromSwipes(
        swipes: const [],
        matchCount: 7,
        genrePreferences: preferences,
      );

      expect(statistics.matchCount, 7);
      expect(statistics.genrePreferences, preferences);
    });

    test('ohne Swipes sind alle Zähler 0, ohne Fehler', () {
      final statistics = UserStatistics.fromSwipes(
        swipes: const [],
        matchCount: 0,
        genrePreferences: UserGenrePreferences.empty,
      );

      expect(statistics.swipeCount, 0);
      expect(statistics.likeCount, 0);
      expect(statistics.dislikeCount, 0);
      expect(statistics.watchlistCount, 0);
    });
  });
}
