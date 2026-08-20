import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:film2watch/models/movie_swipe.dart';
import 'package:film2watch/providers/auth_provider.dart';
import 'package:film2watch/providers/group_provider.dart';
import 'package:film2watch/providers/swipe_provider.dart';
import 'package:film2watch/repositories/group_repository.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _seedSwipe(
  FakeFirebaseFirestore firestore,
  String groupId,
  String uid,
  int movieId,
  SwipeDecision decision,
  DateTime updatedAt,
) {
  return firestore.collection('groups').doc(groupId).collection('swipes').doc('${uid}_$movieId').set({
    'uid': uid,
    'movie_id': movieId,
    'decision': decision.name,
    'created_at': Timestamp.fromDate(updatedAt),
    'updated_at': Timestamp.fromDate(updatedAt),
  });
}

void main() {
  group('groupWatchlistProvider', () {
    late FakeFirebaseFirestore firestore;
    late ProviderContainer container;
    late GroupRepository groupRepository;
    late String groupId;

    setUp(() async {
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
      await container.read(authStateChangesProvider.future);

      groupRepository = GroupRepository(firestore);
      final group = await groupRepository.createGroup(name: 'Filmabend', creatorUid: 'alice');
      groupId = group.id;
      await groupRepository.acceptInvitation(groupId: groupId, inviteeUid: 'bob');
    });

    /// Wärmt beide für [groupWatchlistProvider] nötigen Stream-Provider vor
    /// (siehe `all_my_matches_provider_test.dart` für die ausführliche
    /// Begründung: ein reines `container.read(provider.future)` ohne aktiven
    /// Listener liefert bei verketteten StreamProvidern sonst nie).
    Future<List<WatchlistEntry>> readWatchlist() async {
      container.listen(groupWatchlistSwipesProvider(groupId), (previous, next) {});
      container.listen(groupMembersProvider(groupId), (previous, next) {});
      await container.read(groupWatchlistSwipesProvider(groupId).future);
      await container.read(groupMembersProvider(groupId).future);
      return container.read(groupWatchlistProvider(groupId)).value ?? const [];
    }

    test('liefert eine leere Liste, wenn niemand etwas vorgemerkt hat', () async {
      final entries = await readWatchlist();
      expect(entries, isEmpty);
    });

    test('liefert einen Eintrag, wenn genau ein Mitglied einen Film vorgemerkt hat', () async {
      await _seedSwipe(firestore, groupId, 'alice', 100, SwipeDecision.watchlist, DateTime(2026, 1, 1));

      final entries = await readWatchlist();

      expect(entries, hasLength(1));
      expect(entries.first.movieId, 100);
      expect(entries.first.memberUids, ['alice']);
    });

    test('mehrere Filme auf der Watchlist erzeugen mehrere Einträge, neueste zuerst', () async {
      await _seedSwipe(firestore, groupId, 'alice', 100, SwipeDecision.watchlist, DateTime(2026, 1, 1));
      await _seedSwipe(firestore, groupId, 'bob', 200, SwipeDecision.watchlist, DateTime(2026, 1, 5));

      final entries = await readWatchlist();

      expect(entries.map((e) => e.movieId).toList(), [200, 100]);
    });

    test('mehrere Mitglieder mit demselben Film werden zu einem Eintrag mit mehreren UIDs zusammengefasst',
        () async {
      await _seedSwipe(firestore, groupId, 'alice', 100, SwipeDecision.watchlist, DateTime(2026, 1, 1));
      await _seedSwipe(firestore, groupId, 'bob', 100, SwipeDecision.watchlist, DateTime(2026, 1, 2));

      final entries = await readWatchlist();

      expect(entries, hasLength(1));
      expect(entries.first.memberUids, ['alice', 'bob']);
    });

    test('Like-/Dislike-/Skip-Swipes tauchen nicht in der Watchlist auf', () async {
      await _seedSwipe(firestore, groupId, 'alice', 100, SwipeDecision.like, DateTime(2026, 1, 1));
      await _seedSwipe(firestore, groupId, 'alice', 101, SwipeDecision.dislike, DateTime(2026, 1, 1));
      await _seedSwipe(firestore, groupId, 'alice', 102, SwipeDecision.skip, DateTime(2026, 1, 1));
      await _seedSwipe(firestore, groupId, 'alice', 103, SwipeDecision.watchlist, DateTime(2026, 1, 1));

      final entries = await readWatchlist();

      expect(entries.map((e) => e.movieId).toList(), [103]);
    });

    test('Watchlist-Einträge ehemaliger Mitglieder werden nicht gezählt', () async {
      await _seedSwipe(firestore, groupId, 'bob', 100, SwipeDecision.watchlist, DateTime(2026, 1, 1));
      await groupRepository.removeMember(groupId, 'bob');

      final entries = await readWatchlist();

      expect(entries, isEmpty);
    });

    test('Watchlist ist gruppenbezogen - ein Eintrag in Gruppe A erscheint nicht in Gruppe B', () async {
      final groupB = await groupRepository.createGroup(name: 'WG-Kino', creatorUid: 'alice');
      await _seedSwipe(firestore, groupId, 'alice', 100, SwipeDecision.watchlist, DateTime(2026, 1, 1));

      container.listen(groupWatchlistSwipesProvider(groupB.id), (previous, next) {});
      container.listen(groupMembersProvider(groupB.id), (previous, next) {});
      await container.read(groupWatchlistSwipesProvider(groupB.id).future);
      await container.read(groupMembersProvider(groupB.id).future);
      final entriesB = container.read(groupWatchlistProvider(groupB.id)).value ?? const [];

      expect(entriesB, isEmpty);
    });
  });
}
