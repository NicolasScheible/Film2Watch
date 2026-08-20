import 'package:film2watch/components/movies/swipe_card.dart';
import 'package:film2watch/models/movie.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Movie _movie({int tmdbId = 1}) => Movie(
      tmdbId: tmdbId,
      title: 'Testfilm',
      originalTitle: 'Testfilm',
      overview: 'Eine Beschreibung.',
      posterPath: null,
      backdropPath: null,
      releaseDate: DateTime(2024, 1, 1),
      genreIds: const [],
      genres: const ['Drama'],
      voteAverage: 7.5,
      voteCount: 100,
      runtime: 120,
      originalLanguage: 'en',
    );

void main() {
  group('SwipeCard', () {
    testWidgets('Wischen nach unten löst Skip aus (echte Drag-Geste)', (tester) async {
      SwipeCardDirection? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SwipeCard(movie: _movie(), onSwiped: (direction) => result = direction),
          ),
        ),
      );

      await tester.drag(find.byType(SwipeCard), const Offset(0, 300));
      await tester.pumpAndSettle();

      expect(result, SwipeCardDirection.skip);
    });

    testWidgets('Wischen nach rechts löst weiterhin Like aus (Regression)', (tester) async {
      SwipeCardDirection? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SwipeCard(movie: _movie(), onSwiped: (direction) => result = direction),
          ),
        ),
      );

      await tester.drag(find.byType(SwipeCard), const Offset(300, 0));
      await tester.pumpAndSettle();

      expect(result, SwipeCardDirection.like);
    });

    testWidgets('Wischen nach links löst weiterhin Dislike aus (Regression)', (tester) async {
      SwipeCardDirection? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SwipeCard(movie: _movie(), onSwiped: (direction) => result = direction),
          ),
        ),
      );

      await tester.drag(find.byType(SwipeCard), const Offset(-300, 0));
      await tester.pumpAndSettle();

      expect(result, SwipeCardDirection.dislike);
    });

    testWidgets('ein kurzer Drag unterhalb der Schwelle löst nichts aus', (tester) async {
      SwipeCardDirection? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SwipeCard(movie: _movie(), onSwiped: (direction) => result = direction),
          ),
        ),
      );

      await tester.drag(find.byType(SwipeCard), const Offset(0, 40));
      await tester.pumpAndSettle();

      expect(result, isNull);
    });

    testWidgets('triggerSkip() über den GlobalKey löst dieselbe Aktion wie die Geste aus', (tester) async {
      SwipeCardDirection? result;
      final key = GlobalKey<SwipeCardState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SwipeCard(key: key, movie: _movie(), onSwiped: (direction) => result = direction),
          ),
        ),
      );

      key.currentState!.triggerSkip();
      await tester.pumpAndSettle();

      expect(result, SwipeCardDirection.skip);
    });

    testWidgets('deaktivierte Karte reagiert nicht auf Skip-Geste', (tester) async {
      SwipeCardDirection? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SwipeCard(
              movie: _movie(),
              isEnabled: false,
              onSwiped: (direction) => result = direction,
            ),
          ),
        ),
      );

      await tester.drag(find.byType(SwipeCard), const Offset(0, 300));
      await tester.pumpAndSettle();

      expect(result, isNull);
    });
  });
}
