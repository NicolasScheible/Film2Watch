import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:film2watch/models/movie_swipe.dart';
import 'package:film2watch/repositories/group_repository.dart';
import 'package:film2watch/repositories/premium_repository.dart';
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

    test('genre_ids ist Teil des Firestore-Mappings, Default ist eine leere Liste', () async {
      final firestore = FakeFirebaseFirestore();
      final createdAt = DateTime(2026, 1, 1, 12);
      final withGenres = MovieSwipe(
        uid: 'alice',
        movieId: 551,
        decision: SwipeDecision.like,
        createdAt: createdAt,
        updatedAt: createdAt,
        genreIds: const [27, 878],
      );
      final withoutGenres = MovieSwipe(
        uid: 'alice',
        movieId: 552,
        decision: SwipeDecision.like,
        createdAt: createdAt,
        updatedAt: createdAt,
      );

      final ref1 = firestore.collection('groups').doc('g1').collection('swipes').doc('alice_551');
      await ref1.set(withGenres.toFirestore());
      final ref2 = firestore.collection('groups').doc('g1').collection('swipes').doc('alice_552');
      await ref2.set(withoutGenres.toFirestore());

      expect(MovieSwipe.fromFirestore(await ref1.get()).genreIds, [27, 878]);
      expect(MovieSwipe.fromFirestore(await ref2.get()).genreIds, isEmpty);
    });

    test('ein Legacy-Dokument ohne genre_ids-Feld wird robust als leere Liste gelesen', () async {
      final firestore = FakeFirebaseFirestore();
      final ref = firestore.collection('groups').doc('g1').collection('swipes').doc('alice_553');
      await ref.set({
        'uid': 'alice',
        'movie_id': 553,
        'decision': 'like',
        'created_at': Timestamp.now(),
        'updated_at': Timestamp.now(),
        // bewusst kein 'genre_ids'-Feld - simuliert ein vor diesem Schritt
        // angelegtes Dokument.
      });

      expect(MovieSwipe.fromFirestore(await ref.get()).genreIds, isEmpty);
    });
  });

  group('SwipeService', () {
    late FakeFirebaseFirestore firestore;
    late GroupRepository groupRepository;
    late SwipeRepository swipeRepository;
    late PremiumRepository premiumRepository;
    late SwipeService swipeService;
    late String groupId;

    setUp(() async {
      firestore = FakeFirebaseFirestore();
      groupRepository = GroupRepository(firestore);
      swipeRepository = SwipeRepository(firestore);
      premiumRepository = PremiumRepository(firestore);
      swipeService = SwipeService(swipeRepository, groupRepository, premiumRepository);

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

    test('Skip speichert eine Entscheidung mit decision == skip', () async {
      await swipeService.skipMovie(groupId: groupId, uid: 'alice', movieId: 556);

      final swipe = await swipeRepository.getSwipe(groupId: groupId, uid: 'alice', movieId: 556);
      expect(swipe, isNotNull);
      expect(swipe!.decision, SwipeDecision.skip);
    });

    test('Skip ist userbezogen - ein zweites Mitglied kann denselben Film unabhängig bewerten', () async {
      await swipeService.skipMovie(groupId: groupId, uid: 'alice', movieId: 557);
      await swipeService.likeMovie(groupId: groupId, uid: 'bob', movieId: 557);

      final aliceSwipe = await swipeRepository.getSwipe(groupId: groupId, uid: 'alice', movieId: 557);
      final bobSwipe = await swipeRepository.getSwipe(groupId: groupId, uid: 'bob', movieId: 557);
      expect(aliceSwipe!.decision, SwipeDecision.skip);
      expect(bobSwipe!.decision, SwipeDecision.like);
    });

    test('geskippter Film wird von getSwipedMovieIds erkannt (wird aus der Warteschlange ausgeblendet)', () async {
      await swipeService.skipMovie(groupId: groupId, uid: 'bob', movieId: 558);

      final swipedIds = await swipeRepository.getSwipedMovieIds(groupId: groupId, uid: 'bob');
      expect(swipedIds, contains(558));
    });

    test('doppeltes Skip erzeugt kein zweites Dokument (Idempotenz)', () async {
      await swipeService.skipMovie(groupId: groupId, uid: 'alice', movieId: 559);
      await swipeService.skipMovie(groupId: groupId, uid: 'alice', movieId: 559);

      final snapshot = await firestore
          .collection('groups')
          .doc(groupId)
          .collection('swipes')
          .where('movie_id', isEqualTo: 559)
          .get();
      expect(snapshot.docs, hasLength(1));
    });

    test('Like -> Skip aktualisiert die bestehende Entscheidung statt ein neues Dokument anzulegen', () async {
      await swipeService.likeMovie(groupId: groupId, uid: 'alice', movieId: 560);
      await swipeService.skipMovie(groupId: groupId, uid: 'alice', movieId: 560);

      final swipe = await swipeRepository.getSwipe(groupId: groupId, uid: 'alice', movieId: 560);
      expect(swipe!.decision, SwipeDecision.skip);

      final snapshot = await firestore
          .collection('groups')
          .doc(groupId)
          .collection('swipes')
          .where('movie_id', isEqualTo: 560)
          .get();
      expect(snapshot.docs, hasLength(1));
    });

    test('Skip durch ein Nicht-Mitglied schlägt fehl', () async {
      expect(
        () => swipeService.skipMovie(groupId: groupId, uid: 'carol', movieId: 561),
        throwsA(isA<GroupActionException>()),
      );
    });

    test('genre_ids wird beim Anlegen gespeichert (§7/§18 Boost-Algorithmus)', () async {
      await swipeService.likeMovie(
        groupId: groupId,
        uid: 'alice',
        movieId: 563,
        genreIds: const [27, 878],
      );

      final swipe = await swipeRepository.getSwipe(groupId: groupId, uid: 'alice', movieId: 563);
      expect(swipe!.genreIds, [27, 878]);
    });

    test('genre_ids bleibt beim erneuten Bewerten desselben Films unverändert', () async {
      await swipeService.likeMovie(
        groupId: groupId,
        uid: 'alice',
        movieId: 564,
        genreIds: const [27],
      );
      // Ein erneutes Bewerten übergibt bewusst KEINE genre_ids (Default
      // const []) - simuliert z. B. einen Aufrufer, der die Genres nicht
      // erneut kennt. Die ursprünglich gespeicherten genre_ids dürfen
      // trotzdem nicht verschwinden.
      await swipeService.dislikeMovie(groupId: groupId, uid: 'alice', movieId: 564);

      final swipe = await swipeRepository.getSwipe(groupId: groupId, uid: 'alice', movieId: 564);
      expect(swipe!.decision, SwipeDecision.dislike);
      expect(swipe.genreIds, [27]);
    });

    test('ohne genre_ids-Angabe ist die Liste leer (Rückwärtskompatibilität)', () async {
      await swipeService.likeMovie(groupId: groupId, uid: 'alice', movieId: 565);

      final swipe = await swipeRepository.getSwipe(groupId: groupId, uid: 'alice', movieId: 565);
      expect(swipe!.genreIds, isEmpty);
    });

    test('Watchlist speichert eine Entscheidung mit decision == watchlist', () async {
      await swipeService.watchlistMovie(groupId: groupId, uid: 'alice', movieId: 562);

      final swipe = await swipeRepository.getSwipe(groupId: groupId, uid: 'alice', movieId: 562);
      expect(swipe, isNotNull);
      expect(swipe!.decision, SwipeDecision.watchlist);
    });

    test('Watchlist ist userbezogen - ein zweites Mitglied kann denselben Film unabhängig bewerten', () async {
      await swipeService.watchlistMovie(groupId: groupId, uid: 'alice', movieId: 563);
      await swipeService.likeMovie(groupId: groupId, uid: 'bob', movieId: 563);

      final aliceSwipe = await swipeRepository.getSwipe(groupId: groupId, uid: 'alice', movieId: 563);
      final bobSwipe = await swipeRepository.getSwipe(groupId: groupId, uid: 'bob', movieId: 563);
      expect(aliceSwipe!.decision, SwipeDecision.watchlist);
      expect(bobSwipe!.decision, SwipeDecision.like);
    });

    test('Film auf der Watchlist wird von getSwipedMovieIds erkannt (wird aus der Warteschlange ausgeblendet)',
        () async {
      await swipeService.watchlistMovie(groupId: groupId, uid: 'bob', movieId: 564);

      final swipedIds = await swipeRepository.getSwipedMovieIds(groupId: groupId, uid: 'bob');
      expect(swipedIds, contains(564));
    });

    test('doppelte Watchlist-Aktion erzeugt kein zweites Dokument (Idempotenz)', () async {
      await swipeService.watchlistMovie(groupId: groupId, uid: 'alice', movieId: 565);
      await swipeService.watchlistMovie(groupId: groupId, uid: 'alice', movieId: 565);

      final snapshot = await firestore
          .collection('groups')
          .doc(groupId)
          .collection('swipes')
          .where('movie_id', isEqualTo: 565)
          .get();
      expect(snapshot.docs, hasLength(1));
    });

    test('Like -> Watchlist aktualisiert die bestehende Entscheidung statt ein neues Dokument anzulegen', () async {
      await swipeService.likeMovie(groupId: groupId, uid: 'alice', movieId: 566);
      await swipeService.watchlistMovie(groupId: groupId, uid: 'alice', movieId: 566);

      final swipe = await swipeRepository.getSwipe(groupId: groupId, uid: 'alice', movieId: 566);
      expect(swipe!.decision, SwipeDecision.watchlist);

      final snapshot = await firestore
          .collection('groups')
          .doc(groupId)
          .collection('swipes')
          .where('movie_id', isEqualTo: 566)
          .get();
      expect(snapshot.docs, hasLength(1));
    });

    test('Watchlist durch ein Nicht-Mitglied schlägt fehl', () async {
      expect(
        () => swipeService.watchlistMovie(groupId: groupId, uid: 'carol', movieId: 567),
        throwsA(isA<GroupActionException>()),
      );
    });

    test('removeFromWatchlist entfernt den eigenen Watchlist-Eintrag vollständig', () async {
      await swipeService.watchlistMovie(groupId: groupId, uid: 'alice', movieId: 700);

      await swipeService.removeFromWatchlist(groupId: groupId, uid: 'alice', movieId: 700);

      final swipe = await swipeRepository.getSwipe(groupId: groupId, uid: 'alice', movieId: 700);
      expect(swipe, isNull);
    });

    test('removeFromWatchlist lässt den Film wieder als unbewerteten Kandidaten erscheinen', () async {
      await swipeService.watchlistMovie(groupId: groupId, uid: 'alice', movieId: 701);
      await swipeService.removeFromWatchlist(groupId: groupId, uid: 'alice', movieId: 701);

      final swipedIds = await swipeRepository.getSwipedMovieIds(groupId: groupId, uid: 'alice');
      expect(swipedIds, isNot(contains(701)));
    });

    test('nach removeFromWatchlist kann derselbe Film normal neu geliked werden', () async {
      await swipeService.watchlistMovie(groupId: groupId, uid: 'alice', movieId: 701);
      await swipeService.removeFromWatchlist(groupId: groupId, uid: 'alice', movieId: 701);

      await swipeService.likeMovie(groupId: groupId, uid: 'alice', movieId: 701);

      final swipe = await swipeRepository.getSwipe(groupId: groupId, uid: 'alice', movieId: 701);
      expect(swipe!.decision, SwipeDecision.like);
    });

    test('removeFromWatchlist eines nicht existierenden Eintrags wirft eine verständliche Exception', () async {
      expect(
        () => swipeService.removeFromWatchlist(groupId: groupId, uid: 'alice', movieId: 702),
        throwsA(isA<GroupActionException>()),
      );
    });

    test('removeFromWatchlist auf einem Like/Dislike/Skip-Eintrag wirft eine verständliche Exception (kein Löschen)',
        () async {
      await swipeService.likeMovie(groupId: groupId, uid: 'alice', movieId: 703);

      expect(
        () => swipeService.removeFromWatchlist(groupId: groupId, uid: 'alice', movieId: 703),
        throwsA(isA<GroupActionException>()),
      );
      final swipe = await swipeRepository.getSwipe(groupId: groupId, uid: 'alice', movieId: 703);
      expect(swipe, isNotNull, reason: 'Der Like-Swipe darf nicht gelöscht worden sein');
      expect(swipe!.decision, SwipeDecision.like);
    });

    test('removeFromWatchlist entfernt nur den eigenen Eintrag, der Watchlist-Eintrag eines anderen Mitglieds bleibt unverändert',
        () async {
      await swipeService.watchlistMovie(groupId: groupId, uid: 'alice', movieId: 704);
      await swipeService.watchlistMovie(groupId: groupId, uid: 'bob', movieId: 704);

      await swipeService.removeFromWatchlist(groupId: groupId, uid: 'alice', movieId: 704);

      final aliceSwipe = await swipeRepository.getSwipe(groupId: groupId, uid: 'alice', movieId: 704);
      final bobSwipe = await swipeRepository.getSwipe(groupId: groupId, uid: 'bob', movieId: 704);
      expect(aliceSwipe, isNull);
      expect(bobSwipe, isNotNull);
      expect(bobSwipe!.decision, SwipeDecision.watchlist);
    });

    test('removeFromWatchlist durch ein Nicht-Mitglied schlägt fehl', () async {
      await swipeService.watchlistMovie(groupId: groupId, uid: 'alice', movieId: 705);

      expect(
        () => swipeService.removeFromWatchlist(groupId: groupId, uid: 'carol', movieId: 705),
        throwsA(isA<GroupActionException>()),
      );
    });

    // Super Swipe (§6/§15, Premium-Feature) - rein binäres Gating, kein
    // Kontingent (mit dem Produktverantwortlichen abgestimmt).
    test('Premium-User kann einen Film super-swipen', () async {
      await firestore.collection('premium_status').doc('alice').set({'is_premium': true});

      await swipeService.superSwipeMovie(groupId: groupId, uid: 'alice', movieId: 800);

      final swipe = await swipeRepository.getSwipe(groupId: groupId, uid: 'alice', movieId: 800);
      expect(swipe!.decision, SwipeDecision.superSwipe);
    });

    test('super-swipe wird als "super" in Firestore gespeichert (§17.4-Schema)', () async {
      await firestore.collection('premium_status').doc('alice').set({'is_premium': true});

      await swipeService.superSwipeMovie(groupId: groupId, uid: 'alice', movieId: 801);

      final doc = await firestore
          .collection('groups')
          .doc(groupId)
          .collection('swipes')
          .doc('alice_801')
          .get();
      expect(doc.data()!['decision'], 'super');
    });

    test('ein Free-User (kein premium_status-Dokument) kann nicht super-swipen', () async {
      expect(
        () => swipeService.superSwipeMovie(groupId: groupId, uid: 'alice', movieId: 802),
        throwsA(isA<GroupActionException>()),
      );
    });

    test('ein User mit is_premium == false kann nicht super-swipen', () async {
      await firestore.collection('premium_status').doc('alice').set({'is_premium': false});

      expect(
        () => swipeService.superSwipeMovie(groupId: groupId, uid: 'alice', movieId: 803),
        throwsA(isA<GroupActionException>()),
      );
    });

    test('der Premium-Status eines anderen Users macht einen Free-User nicht selbst premium', () async {
      await firestore.collection('premium_status').doc('bob').set({'is_premium': true});

      expect(
        () => swipeService.superSwipeMovie(groupId: groupId, uid: 'alice', movieId: 804),
        throwsA(isA<GroupActionException>()),
      );
    });

    test('super-swipen durch ein Nicht-Mitglied schlägt fehl, auch mit Premium', () async {
      await firestore.collection('premium_status').doc('carol').set({'is_premium': true});

      expect(
        () => swipeService.superSwipeMovie(groupId: groupId, uid: 'carol', movieId: 805),
        throwsA(isA<GroupActionException>()),
      );
    });

    test('super-swiped Film wird von getSwipedMovieIds erkannt (wird aus der Warteschlange ausgeblendet)',
        () async {
      await firestore.collection('premium_status').doc('alice').set({'is_premium': true});
      await swipeService.superSwipeMovie(groupId: groupId, uid: 'alice', movieId: 806);

      final swipedIds = await swipeRepository.getSwipedMovieIds(groupId: groupId, uid: 'alice');
      expect(swipedIds, contains(806));
    });

    test('bereits erneutes Super-Swipen desselben Films erzeugt kein zweites Dokument (Idempotenz)', () async {
      await firestore.collection('premium_status').doc('alice').set({'is_premium': true});
      await swipeService.superSwipeMovie(groupId: groupId, uid: 'alice', movieId: 807);
      await swipeService.superSwipeMovie(groupId: groupId, uid: 'alice', movieId: 807);

      final snapshot = await firestore
          .collection('groups')
          .doc(groupId)
          .collection('swipes')
          .where('movie_id', isEqualTo: 807)
          .get();
      expect(snapshot.docs, hasLength(1));
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
