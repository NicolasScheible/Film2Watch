import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/movie_swipe.dart';

/// Kapselt den Firestore-Zugriff auf `groups/{groupId}/swipes`. Dokument-ID
/// ist deterministisch `{uid}_{movieId}` - ein erneutes Bewerten desselben
/// Films durch denselben User erzeugt kein zweites Dokument, sondern
/// aktualisiert die bestehende Entscheidung.
class SwipeRepository {
  SwipeRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _swipes(String groupId) =>
      _firestore.collection('groups').doc(groupId).collection('swipes');

  String _swipeId(String uid, int movieId) => '${uid}_$movieId';

  Future<MovieSwipe?> getSwipe({
    required String groupId,
    required String uid,
    required int movieId,
  }) async {
    final snapshot = await _swipes(groupId).doc(_swipeId(uid, movieId)).get();
    return snapshot.exists ? MovieSwipe.fromFirestore(snapshot) : null;
  }

  /// Legt die Entscheidung an oder aktualisiert eine bestehende - niemals ein
  /// zweites Dokument für dasselbe (uid, movieId)-Paar.
  Future<void> setSwipe({
    required String groupId,
    required String uid,
    required int movieId,
    required SwipeDecision decision,
  }) async {
    final ref = _swipes(groupId).doc(_swipeId(uid, movieId));
    final existing = await ref.get();
    final now = DateTime.now();

    if (existing.exists) {
      await ref.update({
        'decision': decision.name,
        'updated_at': Timestamp.fromDate(now),
      });
      return;
    }

    final swipe = MovieSwipe(
      uid: uid,
      movieId: movieId,
      decision: decision,
      createdAt: now,
      updatedAt: now,
    );
    await ref.set(swipe.toFirestore());
  }

  /// Alle Film-IDs, die [uid] in dieser Gruppe bereits bewertet hat -
  /// unabhängig von like/dislike, damit sie beim Swipen nicht erneut
  /// erscheinen.
  Future<Set<int>> getSwipedMovieIds({required String groupId, required String uid}) async {
    final snapshot = await _swipes(groupId).where('uid', isEqualTo: uid).get();
    return snapshot.docs.map((doc) => (doc.data()['movie_id'] as num).toInt()).toSet();
  }

  /// Alle Watchlist-Einträge (`decision == watchlist`) aller Mitglieder
  /// dieser Gruppe, in Echtzeit - Grundlage für den Watchlist-Abgleich
  /// innerhalb der Gruppe ("Du hast vorgemerkt" / "2/4 Mitglieder haben ihn
  /// vorgemerkt"). Die Filterung auf tatsächlich noch aktuelle Mitglieder
  /// übernimmt die aufrufende Provider-Schicht (analog zur bestehenden
  /// Match-Erkennung, die ebenfalls nur aktuelle Mitglieder zählt).
  Stream<List<MovieSwipe>> watchWatchlist(String groupId) {
    return _swipes(groupId)
        .where('decision', isEqualTo: SwipeDecision.watchlist.name)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(MovieSwipe.fromFirestore).toList());
  }

  /// Entfernt die eigene Watchlist-Entscheidung für [movieId] vollständig -
  /// der Film ist danach wieder ein unbewerteter Kandidat und kann erneut in
  /// der Swipe-Queue erscheinen. Die Firestore Rules erlauben `delete`
  /// ausschließlich für den eigenen Swipe mit `decision == 'watchlist'` -
  /// Like/Dislike/Skip bleiben unlöschbar.
  Future<void> removeSwipe({
    required String groupId,
    required String uid,
    required int movieId,
  }) {
    return _swipes(groupId).doc(_swipeId(uid, movieId)).delete();
  }

  /// Alle Like-Entscheidungen aller Mitglieder dieser Gruppe (nicht nur des
  /// aktuellen Users) - Grundlage für den Freundes-Likes-Boost (§7/§18 der
  /// Master-Spezifikation: `friend_likes`-Zähler pro Film). Firestore Rules
  /// erlauben jedem Gruppenmitglied das Lesen aller Swipes der eigenen
  /// Gruppe bereits (`allow read: if isGroupMember(groupId)`) - keine neue
  /// Berechtigung nötig. Die Einschränkung auf tatsächliche Freunde
  /// übernimmt die aufrufende Schicht (`countFriendLikes`).
  Future<List<MovieSwipe>> getGroupLikes(String groupId) async {
    final snapshot =
        await _swipes(groupId).where('decision', isEqualTo: SwipeDecision.like.name).get();
    return snapshot.docs.map(MovieSwipe.fromFirestore).toList();
  }
}
