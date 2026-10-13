import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:film2watch/models/movie_swipe.dart';
import 'package:film2watch/repositories/group_repository.dart';
import 'package:film2watch/repositories/swipe_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// `getAllSwipesForUser` liest den dauerhaften Swipe-Group-Index
/// (`users/{uid}/swiped_groups/{groupId}`, siehe README
/// "Architekturentscheidung"), der in Produktion ausschließlich vom
/// Cloud-Function-Trigger `onSwipeWrittenForGroupIndex` gepflegt wird -
/// `fake_cloud_firestore` führt diesen Trigger nicht aus, daher hier direkt
/// nachgebildet (analog zu allen anderen Tests in dieser Codebase, die den
/// User-Group-Index simulieren).
Future<void> _seedSwipedGroupsIndex(FakeFirebaseFirestore firestore, String uid, String groupId) {
  return firestore.collection('users').doc(uid).collection('swiped_groups').doc(groupId).set({
    'groupId': groupId,
  });
}

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

    test('liefert eine leere Liste, wenn der User in keiner Gruppe jemals geswiped hat', () async {
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
      await _seedSwipedGroupsIndex(firestore, 'alice', group1.id);
      await _seedSwipedGroupsIndex(firestore, 'alice', group2.id);

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
      await _seedSwipedGroupsIndex(firestore, 'alice', group.id);

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
      await _seedSwipedGroupsIndex(firestore, 'alice', group.id);

      final swipes = await swipeRepository.getAllSwipesForUser('alice');
      expect(swipes.length, 1);
      expect(swipes.single.decision, SwipeDecision.watchlist);
    });

    test('eine bekannte Gruppe ohne (mehr) Swipes wirft keine Exception', () async {
      final group = await groupRepository.createGroup(name: 'Gruppe', creatorUid: 'alice');
      // Index-Eintrag existiert (es wurde dort einmal geswiped), aber der
      // einzige Swipe wurde inzwischen wieder entfernt (Watchlist-Entfernen)
      // - der Index-Eintrag selbst bleibt laut Architektur bestehen.
      await _seedSwipedGroupsIndex(firestore, 'alice', group.id);

      expect(await swipeRepository.getAllSwipesForUser('alice'), isEmpty);
    });

    test('ein User ohne jemals geswipete Gruppe erhält ein leeres Ergebnis, kein Fehler', () async {
      await groupRepository.createGroup(name: 'Gruppe', creatorUid: 'bob');

      expect(await swipeRepository.getAllSwipesForUser('alice'), isEmpty);
    });

    test('berücksichtigt weiterhin Swipes aus einer Gruppe, die alice inzwischen verlassen hat (PO-Entscheidung: historische Swipes zählen)', () async {
      final group = await groupRepository.createGroup(name: 'Gruppe', creatorUid: 'alice');
      await swipeRepository.setSwipe(
        groupId: group.id,
        uid: 'alice',
        movieId: 1,
        decision: SwipeDecision.like,
      );
      // Der Swipe-Group-Index bleibt nach dem Verlassen bestehen (anders als
      // der aktuelle Mitgliedschafts-Index `users/{uid}/groups`), daher wird
      // hier bewusst NUR der Swipe-Group-Index gesetzt, nicht die aktuelle
      // Mitgliedschaft selbst entfernt (die ist für diese Methode
      // irrelevant).
      await _seedSwipedGroupsIndex(firestore, 'alice', group.id);
      await groupRepository.removeMember(group.id, 'alice');

      final swipes = await swipeRepository.getAllSwipesForUser('alice');
      expect(swipes.length, 1);
      expect(swipes.single.movieId, 1);
    });
  });
}
