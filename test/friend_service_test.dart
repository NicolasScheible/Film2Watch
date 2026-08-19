import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:film2watch/models/friend_search_result.dart';
import 'package:film2watch/repositories/friend_repository.dart';
import 'package:film2watch/repositories/user_repository.dart';
import 'package:film2watch/services/friend_service.dart';
import 'package:film2watch/utils/friend_exceptions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late UserRepository userRepository;
  late FriendRepository friendRepository;
  late FriendService friendService;

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    userRepository = UserRepository(firestore);
    friendRepository = FriendRepository(firestore);
    friendService = FriendService(friendRepository, userRepository);

    await userRepository.ensureUserDocument(
      uid: 'alice',
      email: 'alice@film2watch.app',
      name: 'Alice',
    );
    await userRepository.ensureUserDocument(
      uid: 'bob',
      email: 'bob@film2watch.app',
      name: 'Bob',
    );
  });

  test('eigener Friend Code kann nicht als Freund hinzugefügt werden', () async {
    final ownCode = (await userRepository.getUser('alice'))!.friendCode;

    final result = await friendService.searchByFriendCode(myUid: 'alice', code: ownCode);

    expect(result, isA<FriendSearchOwnCode>());
  });

  test('unbekannter Friend Code wird korrekt behandelt', () async {
    final result = await friendService.searchByFriendCode(myUid: 'alice', code: 'FILM-0000');

    expect(result, isA<FriendSearchNotFound>());
  });

  test('doppelte Freundschaft wird verhindert', () async {
    await friendRepository.sendFriendRequest(fromUid: 'alice', toUid: 'bob');
    await friendRepository.acceptRequest(fromUid: 'alice', toUid: 'bob');

    expect(
      () => friendRepository.sendFriendRequest(fromUid: 'alice', toUid: 'bob'),
      throwsA(isA<FriendActionException>()),
    );
  });

  test('doppelte Anfrage wird verhindert', () async {
    await friendRepository.sendFriendRequest(fromUid: 'alice', toUid: 'bob');

    expect(
      () => friendRepository.sendFriendRequest(fromUid: 'alice', toUid: 'bob'),
      throwsA(isA<FriendActionException>()),
    );
  });

  test('Anfrage kann angenommen werden', () async {
    await friendRepository.sendFriendRequest(fromUid: 'alice', toUid: 'bob');

    await friendRepository.acceptRequest(fromUid: 'alice', toUid: 'bob');

    expect(await friendRepository.areFriends('alice', 'bob'), isTrue);
    expect(await friendRepository.requestExists(fromUid: 'alice', toUid: 'bob'), isFalse);
  });

  test('Anfrage kann abgelehnt werden', () async {
    await friendRepository.sendFriendRequest(fromUid: 'alice', toUid: 'bob');

    await friendRepository.declineRequest(fromUid: 'alice', toUid: 'bob');

    expect(await friendRepository.requestExists(fromUid: 'alice', toUid: 'bob'), isFalse);
    expect(await friendRepository.areFriends('alice', 'bob'), isFalse);
  });

  test('Freundschaft kann entfernt werden', () async {
    await friendRepository.sendFriendRequest(fromUid: 'alice', toUid: 'bob');
    await friendRepository.acceptRequest(fromUid: 'alice', toUid: 'bob');

    await friendRepository.removeFriend('alice', 'bob');

    expect(await friendRepository.areFriends('alice', 'bob'), isFalse);
  });

  test('User-Profil kann aktualisiert werden', () async {
    await userRepository.updateName('alice', 'Alice Neu');

    final updated = await userRepository.getUser('alice');

    expect(updated!.name, 'Alice Neu');
  });

  test('Friend Code bleibt beim Profil-Update unverändert', () async {
    final before = (await userRepository.getUser('alice'))!.friendCode;

    await userRepository.updateName('alice', 'Alice Neu');

    final after = (await userRepository.getUser('alice'))!.friendCode;
    expect(after, before);
  });
}
