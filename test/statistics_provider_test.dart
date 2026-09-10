import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:film2watch/models/movie_swipe.dart';
import 'package:film2watch/providers/auth_provider.dart';
import 'package:film2watch/providers/group_provider.dart';
import 'package:film2watch/providers/match_provider.dart';
import 'package:film2watch/providers/statistics_provider.dart';
import 'package:film2watch/repositories/group_repository.dart';
import 'package:film2watch/repositories/swipe_repository.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _seedMatch(FakeFirebaseFirestore firestore, String groupId, int movieId) {
  return firestore.collection('groups').doc(groupId).collection('matches').doc('$movieId').set({
    'movie_id': movieId,
    'member_uids': ['alice'],
    'matched_at': Timestamp.now(),
  });
}

void main() {
  group('userStatisticsProvider (§15: Detaillierte Statistiken)', () {
    late FakeFirebaseFirestore firestore;
    late ProviderContainer container;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'alice', email: 'alice@film2watch.app'),
        signedIn: true,
      );
      container = ProviderContainer(
        overrides: [
          firebaseAuthProvider.overrideWithValue(auth),
          firestoreProvider.overrideWithValue(firestore),
        ],
      );
      addTearDown(container.dispose);
      container.listen(authStateChangesProvider, (previous, next) {});
    });

    /// Wartet, bis `myGroupsProvider` und alle `groupMatchesProvider`-Streams
    /// für [groupIds] ihr erstes Firestore-Snapshot geliefert haben - exakt
    /// dieselbe Notwendigkeit wie in `all_my_matches_provider_test.dart`, da
    /// `userStatisticsProvider` `allMyMatchesProvider` nur per `.value` liest,
    /// ohne selbst auf dessen Streams zu warten.
    Future<void> settleMatches(List<String> groupIds) async {
      container.listen(myGroupsProvider, (previous, next) {});
      await container.read(myGroupsProvider.future);
      for (final groupId in groupIds) {
        container.listen(groupMatchesProvider(groupId), (previous, next) {});
        await container.read(groupMatchesProvider(groupId).future);
      }
    }

    test('liefert UserStatistics.empty, solange kein User eingeloggt ist', () async {
      final freshContainer = ProviderContainer(
        overrides: [
          firebaseAuthProvider.overrideWithValue(
            MockFirebaseAuth(signedIn: false),
          ),
          firestoreProvider.overrideWithValue(firestore),
        ],
      );
      addTearDown(freshContainer.dispose);
      freshContainer.listen(authStateChangesProvider, (previous, next) {});
      await freshContainer.read(authStateChangesProvider.future);

      final statistics = await freshContainer.read(userStatisticsProvider.future);
      expect(statistics.swipeCount, 0);
      expect(statistics.matchCount, 0);
    });

    test('alle Zähler sind 0, wenn alice noch nie geswiped hat und in keiner Gruppe ist', () async {
      await container.read(authStateChangesProvider.future);
      await settleMatches(const []);

      final statistics = await container.read(userStatisticsProvider.future);
      expect(statistics.swipeCount, 0);
      expect(statistics.likeCount, 0);
      expect(statistics.dislikeCount, 0);
      expect(statistics.watchlistCount, 0);
      expect(statistics.matchCount, 0);
    });

    test('aggregiert Swipes über mehrere Gruppen hinweg zu Likes/Dislikes/Watchlist', () async {
      await container.read(authStateChangesProvider.future);
      final groupRepository = GroupRepository(firestore);
      final swipeRepository = SwipeRepository(firestore);
      final groupA = await groupRepository.createGroup(name: 'Gruppe A', creatorUid: 'alice');
      final groupB = await groupRepository.createGroup(name: 'Gruppe B', creatorUid: 'alice');

      await swipeRepository.setSwipe(
        groupId: groupA.id,
        uid: 'alice',
        movieId: 1,
        decision: SwipeDecision.like,
      );
      await swipeRepository.setSwipe(
        groupId: groupA.id,
        uid: 'alice',
        movieId: 2,
        decision: SwipeDecision.dislike,
      );
      await swipeRepository.setSwipe(
        groupId: groupB.id,
        uid: 'alice',
        movieId: 3,
        decision: SwipeDecision.watchlist,
      );
      // Ein Swipe eines ANDEREN Mitglieds - darf alices Statistik nicht
      // beeinflussen.
      await swipeRepository.setSwipe(
        groupId: groupA.id,
        uid: 'bob',
        movieId: 4,
        decision: SwipeDecision.like,
      );

      await settleMatches([groupA.id, groupB.id]);

      final statistics = await container.read(userStatisticsProvider.future);
      expect(statistics.swipeCount, 3);
      expect(statistics.likeCount, 1);
      expect(statistics.dislikeCount, 1);
      expect(statistics.watchlistCount, 1);
    });

    test('zählt Matches aus mehreren Gruppen zusammen', () async {
      await container.read(authStateChangesProvider.future);
      final groupRepository = GroupRepository(firestore);
      final groupA = await groupRepository.createGroup(name: 'Gruppe A', creatorUid: 'alice');
      final groupB = await groupRepository.createGroup(name: 'Gruppe B', creatorUid: 'alice');
      await _seedMatch(firestore, groupA.id, 100);
      await _seedMatch(firestore, groupB.id, 200);

      await settleMatches([groupA.id, groupB.id]);

      final statistics = await container.read(userStatisticsProvider.future);
      expect(statistics.matchCount, 2);
    });

    test('übernimmt die serverseitig vorberechnete Genre-Präferenz unverändert', () async {
      await container.read(authStateChangesProvider.future);
      await firestore.collection('user_preferences').doc('alice').set({
        'genre_affinity': {'28': 12.5},
        'disliked_genres': <String, dynamic>{},
        'top_genres': [28],
        'disliked_cast_ids': <String, dynamic>{},
      });
      await settleMatches(const []);

      final statistics = await container.read(userStatisticsProvider.future);
      expect(statistics.genrePreferences.topGenres, {28});
      expect(statistics.genrePreferences.genreAffinity[28], 12.5);
    });
  });
}
