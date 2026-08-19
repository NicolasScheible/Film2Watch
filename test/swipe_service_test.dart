import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:film2watch/models/movie_swipe.dart';
import 'package:film2watch/repositories/group_repository.dart';
import 'package:film2watch/repositories/swipe_repository.dart';
import 'package:film2watch/services/swipe_service.dart';
import 'package:film2watch/utils/group_exceptions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MovieSwipe', () {
    test('Firestore-Mapping ist verlustfrei (toFirestore/fromFirestore)', () async {
      final firestore = FakeFirebaseFirestore();
      final createdAt = DateTime(2026, 1, 1, 12);
      final swipe = MovieSwipe(
        uid: 'alice',
        movieId: 550,
        decision: SwipeDecision.like,
        createdAt: createdAt,
        updatedAt: createdAt,
      );

      final ref = firestore.collection('groups').doc('g1').collection('swipes').doc('alice_550');
      await ref.set(swipe.toFirestore());
      final loaded = MovieSwipe.fromFirestore(await ref.get());

      expect(loaded.uid, 'alice');
      expect(loaded.movieId, 550);
      expect(loaded.decision, SwipeDecision.like);
      expect(loaded.createdAt, createdAt);
    });
  });

  group('SwipeService', () {
    late FakeFirebaseFirestore firestore;
    late GroupRepository groupRepository;
    late SwipeRepository swipeRepository;
    late SwipeService swipeService;
    late String groupId;

    setUp(() async {
      firestore = FakeFirebaseFirestore();
      groupRepository = GroupRepository(firestore);
      swipeRepository = SwipeRepository(firestore);
      swipeService = SwipeService(swipeRepository, groupRepository);

      final group = await groupRepository.createGroup(name: 'Filmabend', creatorUid: 'alice');
      groupId = group.id;
      await groupRepository.acceptInvitation(groupId: groupId, inviteeUid: 'bob');
    });

    test('Like speichert eine Entscheidung', () async {
      await swipeService.likeMovie(groupId: groupId, uid: 'alice', movieId: 550);

      final swipe = await swipeRepository.getSwipe(groupId: groupId, uid: 'alice', movieId: 550);
      expect(swipe, isNotNull);
      expect(swipe!.decision, SwipeDecision.like);
    });

    test('Dislike speichert eine Entscheidung', () async {
      await swipeService.dislikeMovie(groupId: groupId, uid: 'alice', movieId: 551);

      final swipe = await swipeRepository.getSwipe(groupId: groupId, uid: 'alice', movieId: 551);
      expect(swipe, isNotNull);
      expect(swipe!.decision, SwipeDecision.dislike);
    });

    test('bereits bewerteter Film wird erkannt', () async {
      await swipeService.likeMovie(groupId: groupId, uid: 'bob', movieId: 552);

      final swipedIds = await swipeRepository.getSwipedMovieIds(groupId: groupId, uid: 'bob');
      expect(swipedIds, contains(552));
    });

    test('wiederholtes Liken desselben Films erzeugt kein zweites Dokument', () async {
      await swipeService.likeMovie(groupId: groupId, uid: 'alice', movieId: 553);
      await swipeService.likeMovie(groupId: groupId, uid: 'alice', movieId: 553);

      final snapshot = await firestore
          .collection('groups')
          .doc(groupId)
          .collection('swipes')
          .where('movie_id', isEqualTo: 553)
          .get();
      expect(snapshot.docs, hasLength(1));
    });

    test('Like -> Dislike aktualisiert die bestehende Entscheidung statt ein neues Dokument anzulegen', () async {
      await swipeService.likeMovie(groupId: groupId, uid: 'alice', movieId: 554);
      await swipeService.dislikeMovie(groupId: groupId, uid: 'alice', movieId: 554);

      final swipe = await swipeRepository.getSwipe(groupId: groupId, uid: 'alice', movieId: 554);
      expect(swipe!.decision, SwipeDecision.dislike);

      final snapshot = await firestore
          .collection('groups')
          .doc(groupId)
          .collection('swipes')
          .where('movie_id', isEqualTo: 554)
          .get();
      expect(snapshot.docs, hasLength(1));
    });

    test('Swipe durch ein Nicht-Mitglied schlägt fehl', () async {
      expect(
        () => swipeService.likeMovie(groupId: groupId, uid: 'carol', movieId: 555),
        throwsA(isA<GroupActionException>()),
      );
    });
  });
}
