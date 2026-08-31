import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:film2watch/repositories/user_preferences_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UserPreferencesRepository', () {
    test('liefert UserGenrePreferences.empty, wenn noch kein Dokument existiert', () async {
      final firestore = FakeFirebaseFirestore();
      final repository = UserPreferencesRepository(firestore);

      final prefs = await repository.getPreferences('alice');

      expect(prefs.genreAffinity, isEmpty);
      expect(prefs.dislikedGenres, isEmpty);
      expect(prefs.topGenres, isEmpty);
    });

    test('liest genre_affinity, disliked_genres und top_genres aus einem bestehenden Dokument', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('user_preferences').doc('alice').set({
        'genre_affinity': {'27': 2.5, '878': 1.0},
        'disliked_genres': {'99': 3},
        'top_genres': [27, 878],
        'last_updated': DateTime(2026, 1, 1),
      });
      final repository = UserPreferencesRepository(firestore);

      final prefs = await repository.getPreferences('alice');

      expect(prefs.genreAffinity, {27: 2.5, 878: 1.0});
      expect(prefs.dislikedGenres, {99: 3});
      expect(prefs.topGenres, {27, 878});
    });

    test('die Präferenzen eines anderen Users beeinflussen das Ergebnis nicht', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('user_preferences').doc('bob').set({
        'genre_affinity': {'27': 5.0},
        'disliked_genres': <String, dynamic>{},
        'top_genres': [27],
        'last_updated': DateTime(2026, 1, 1),
      });
      final repository = UserPreferencesRepository(firestore);

      final prefs = await repository.getPreferences('alice');

      expect(prefs.genreAffinity, isEmpty);
      expect(prefs.topGenres, isEmpty);
    });
  });
}
