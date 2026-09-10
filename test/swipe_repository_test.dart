import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:film2watch/models/movie_swipe.dart';
import 'package:film2watch/repositories/group_repository.dart';
import 'package:film2watch/repositories/swipe_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SwipeRepository.getAllSwipesForUser (§15: Detaillierte Statistiken)', () {
    late FakeFirebaseFirestore firestore;
    late SwipeRepository swipeRepository;
    late GroupRepository groupRepository;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      swipeRepository = SwipeRepository(firestore);
      groupRepository = GroupRepository(firestore);
    });

    test('liefert eine leere Liste, wenn der User noch nie geswiped hat', () async {
      expect(await swipeRepository.getAllSwipesForUser('alice'), isEmpty);
    });

    test('liefert alle Swipes von alice über mehrere Gruppen hinweg', () async {
      final group1 = await groupRepository.createGroup(name: 'Gruppe 1', creatorUid: 'alice');
      final group2 = await groupRepository.createGroup(name: 'Gruppe 2', creatorUid: 'alice');

      await swipeRepository.setSwipe(
        groupId: group1.id,
        uid: 'alice',
        movieId: 1,
        decision: SwipeDecision.like,
      );
      await swipeRepository.setSwipe(
        groupId: group2.id,
        uid: 'alice',
        movieId: 2,
        decision: SwipeDecision.dislike,
      );

      final swipes = await swipeRepository.getAllSwipesForUser('alice');
      expect(swipes.length, 2);
      expect(swipes.map((s) => s.movieId).toSet(), {1, 2});
    });

    test('liefert nur die Swipes des angefragten Users, nicht die anderer Mitglieder', () async {
      final group = await groupRepository.createGroup(name: 'Gruppe', creatorUid: 'alice');
      await swipeRepository.setSwipe(
        groupId: group.id,
        uid: 'alice',
        movieId: 1,
        decision: SwipeDecision.like,
      );
      await swipeRepository.setSwipe(
        groupId: group.id,
        uid: 'bob',
        movieId: 1,
        decision: SwipeDecision.dislike,
      );

      final aliceSwipes = await swipeRepository.getAllSwipesForUser('alice');
      expect(aliceSwipes.length, 1);
      expect(aliceSwipes.single.uid, 'alice');
    });

    test('berücksichtigt ein erneutes Bewerten (update statt zweitem Dokument)', () async {
      final group = await groupRepository.createGroup(name: 'Gruppe', creatorUid: 'alice');
      await swipeRepository.setSwipe(
        groupId: group.id,
        uid: 'alice',
        movieId: 1,
        decision: SwipeDecision.like,
      );
      await swipeRepository.setSwipe(
        groupId: group.id,
        uid: 'alice',
        movieId: 1,
        decision: SwipeDecision.watchlist,
      );

      final swipes = await swipeRepository.getAllSwipesForUser('alice');
      expect(swipes.length, 1);
      expect(swipes.single.decision, SwipeDecision.watchlist);
    });
  });
}
