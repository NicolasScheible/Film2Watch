import '../models/movie_swipe.dart';
import '../repositories/group_repository.dart';
import '../repositories/premium_repository.dart';
import '../repositories/swipe_repository.dart';
import '../utils/group_exceptions.dart';

/// Orchestriert das Bewerten von Filmen innerhalb einer Gruppe. Prüft die
/// Mitgliedschaft, bevor überhaupt geschrieben wird (die Firestore Rules
/// erzwingen dasselbe zusätzlich serverseitig).
class SwipeService {
  SwipeService(this._swipeRepository, this._groupRepository, this._premiumRepository);

  final SwipeRepository _swipeRepository;
  final GroupRepository _groupRepository;
  final PremiumRepository _premiumRepository;

  Future<void> likeMovie({
    required String groupId,
    required String uid,
    required int movieId,
    List<int> genreIds = const [],
  }) {
    return _swipe(
      groupId: groupId,
      uid: uid,
      movieId: movieId,
      decision: SwipeDecision.like,
      genreIds: genreIds,
    );
  }

  Future<void> dislikeMovie({
    required String groupId,
    required String uid,
    required int movieId,
    List<int> genreIds = const [],
  }) {
    return _swipe(
      groupId: groupId,
      uid: uid,
      movieId: movieId,
      decision: SwipeDecision.dislike,
      genreIds: genreIds,
    );
  }

  /// Blendet einen Film für [uid] persönlich aus der Warteschlange dieser
  /// Gruppe aus ("Vielleicht später") - zählt bewusst weder als Like noch
  /// als Dislike und beeinflusst damit nie die Match-Erkennung
  /// (`functions/matchEngine.js` prüft ausschließlich `decision == 'like'`)
  /// und nie die Swipes anderer Mitglieder.
  Future<void> skipMovie({
    required String groupId,
    required String uid,
    required int movieId,
    List<int> genreIds = const [],
  }) {
    return _swipe(
      groupId: groupId,
      uid: uid,
      movieId: movieId,
      decision: SwipeDecision.skip,
      genreIds: genreIds,
    );
  }

  /// Setzt einen Film für [uid] persönlich auf "Vielleicht später"
  /// (Watchlist). Wie Skip weder Like noch Dislike - beeinflusst nie die
  /// Match-Erkennung (`functions/matchEngine.js` prüft ausschließlich
  /// `decision == 'like'`) und nie die Swipes anderer Mitglieder. Blendet den
  /// Film ebenfalls dauerhaft aus der eigenen Warteschlange dieser Gruppe aus.
  Future<void> watchlistMovie({
    required String groupId,
    required String uid,
    required int movieId,
    List<int> genreIds = const [],
  }) {
    return _swipe(
      groupId: groupId,
      uid: uid,
      movieId: movieId,
      decision: SwipeDecision.watchlist,
      genreIds: genreIds,
    );
  }

  /// "Super Swipe" (§6/§15, Premium-Feature): "Signalisiert der Gruppe: 'Den
  /// will ich unbedingt sehen!'". Zählt für die Match-Erkennung wie ein Like
  /// (`functions/matchEngine.js`), hat aber (noch) keinen eigenen
  /// Boost-Bonus - die Master-Spezifikation beziffert diesen nicht, das ist
  /// bewusst nicht Teil dieses Schritts. Rein binäres Premium-Gating: kein
  /// Kontingent, kein Zähler - Free-User dürfen es gar nicht nutzen,
  /// Premium-User beliebig oft. Die Firestore Rules erzwingen dieselbe
  /// Prüfung serverseitig zusätzlich (niemals nur clientseitig vertrauen).
  Future<void> superSwipeMovie({
    required String groupId,
    required String uid,
    required int movieId,
    List<int> genreIds = const [],
  }) async {
    final isPremium = await _premiumRepository.isPremium(uid);
    if (!isPremium) {
      throw const GroupActionException('Super Swipe ist ein Premium-Feature.');
    }
    await _swipe(
      groupId: groupId,
      uid: uid,
      movieId: movieId,
      decision: SwipeDecision.superSwipe,
      genreIds: genreIds,
    );
  }

  /// Entfernt [uid]s eigenen Watchlist-Eintrag für [movieId] vollständig -
  /// der Film ist danach wieder ein unbewerteter Kandidat und kann erneut in
  /// der Swipe-Queue erscheinen. Wirft, wenn der bestehende Eintrag gar
  /// keine Watchlist-Entscheidung ist (die Firestore Rules lehnen ein
  /// Löschen von Like/Dislike/Skip ohnehin serverseitig ab - diese Prüfung
  /// liefert dafür clientseitig eine verständliche Fehlermeldung statt einer
  /// rohen Permission-Denied-Exception).
  Future<void> removeFromWatchlist({
    required String groupId,
    required String uid,
    required int movieId,
  }) async {
    final member = await _groupRepository.getMember(groupId, uid);
    if (member == null) {
      throw const GroupActionException('Du bist kein Mitglied dieser Gruppe.');
    }
    final swipe = await _swipeRepository.getSwipe(groupId: groupId, uid: uid, movieId: movieId);
    if (swipe == null || swipe.decision != SwipeDecision.watchlist) {
      throw const GroupActionException('Dieser Film ist nicht auf deiner Watchlist.');
    }
    await _swipeRepository.removeSwipe(groupId: groupId, uid: uid, movieId: movieId);
  }

  Future<void> _swipe({
    required String groupId,
    required String uid,
    required int movieId,
    required SwipeDecision decision,
    List<int> genreIds = const [],
  }) async {
    final member = await _groupRepository.getMember(groupId, uid);
    if (member == null) {
      throw const GroupActionException('Du bist kein Mitglied dieser Gruppe.');
    }
    await _swipeRepository.setSwipe(
      groupId: groupId,
      uid: uid,
      movieId: movieId,
      decision: decision,
      genreIds: genreIds,
    );
  }
}
