import '../models/movie_swipe.dart';
import '../repositories/group_repository.dart';
import '../repositories/swipe_repository.dart';
import '../utils/group_exceptions.dart';

/// Orchestriert das Bewerten von Filmen innerhalb einer Gruppe. Prüft die
/// Mitgliedschaft, bevor überhaupt geschrieben wird (die Firestore Rules
/// erzwingen dasselbe zusätzlich serverseitig).
class SwipeService {
  SwipeService(this._swipeRepository, this._groupRepository);

  final SwipeRepository _swipeRepository;
  final GroupRepository _groupRepository;

  Future<void> likeMovie({required String groupId, required String uid, required int movieId}) {
    return _swipe(groupId: groupId, uid: uid, movieId: movieId, decision: SwipeDecision.like);
  }

  Future<void> dislikeMovie({required String groupId, required String uid, required int movieId}) {
    return _swipe(groupId: groupId, uid: uid, movieId: movieId, decision: SwipeDecision.dislike);
  }

  Future<void> _swipe({
    required String groupId,
    required String uid,
    required int movieId,
    required SwipeDecision decision,
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
    );
  }
}
