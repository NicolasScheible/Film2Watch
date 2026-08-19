import '../models/friend_search_result.dart';
import '../repositories/friend_repository.dart';
import '../repositories/user_repository.dart';

/// Orchestriert die Freundes-Suche und -Verwaltung. Die UI spricht
/// ausschließlich mit diesem Service, nie direkt mit Firestore.
class FriendService {
  FriendService(this._friendRepository, this._userRepository);

  final FriendRepository _friendRepository;
  final UserRepository _userRepository;

  /// Löst einen eingegebenen Freundescode auf und ermittelt, in welchem
  /// Zustand sich die Beziehung zwischen [myUid] und dem gefundenen User
  /// befindet.
  Future<FriendSearchResult> searchByFriendCode({
    required String myUid,
    required String code,
  }) async {
    final normalizedCode = code.trim().toUpperCase();
    final targetUid = await _userRepository.resolveFriendCode(normalizedCode);
    if (targetUid == null) return const FriendSearchNotFound();
    if (targetUid == myUid) return const FriendSearchOwnCode();

    final profile = await _userRepository.getPublicProfile(targetUid);
    if (profile == null) return const FriendSearchNotFound();

    if (await _friendRepository.areFriends(myUid, targetUid)) {
      return FriendSearchAlreadyFriends(profile);
    }
    if (await _friendRepository.requestExists(fromUid: myUid, toUid: targetUid)) {
      return FriendSearchRequestAlreadySent(profile);
    }
    if (await _friendRepository.requestExists(fromUid: targetUid, toUid: myUid)) {
      return FriendSearchIncomingRequestExists(profile);
    }
    return FriendSearchFound(profile);
  }

  Future<void> sendFriendRequest({required String fromUid, required String toUid}) {
    return _friendRepository.sendFriendRequest(fromUid: fromUid, toUid: toUid);
  }

  Future<void> acceptRequest({required String fromUid, required String toUid}) {
    return _friendRepository.acceptRequest(fromUid: fromUid, toUid: toUid);
  }

  Future<void> declineRequest({required String fromUid, required String toUid}) {
    return _friendRepository.declineRequest(fromUid: fromUid, toUid: toUid);
  }

  Future<void> removeFriend(String myUid, String friendUid) {
    return _friendRepository.removeFriend(myUid, friendUid);
  }
}
