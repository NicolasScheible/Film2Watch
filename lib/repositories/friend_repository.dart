import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/friend_request.dart';
import '../utils/friend_exceptions.dart';

/// Kapselt den Firestore-Zugriff auf `friend_requests` und `friendships`.
/// Spiegelt exakt das Sicherheitsmodell aus `firestore.rules` wider:
/// Freundschaften sind ein einzelnes Dokument pro sortiertem Paar
/// (`friendships/{pairId}`), wodurch sie strukturell nie einseitig
/// bestehen können.
class FriendRepository {
  FriendRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _requests =>
      _firestore.collection('friend_requests');

  CollectionReference<Map<String, dynamic>> get _friendships =>
      _firestore.collection('friendships');

  String _requestId(String fromUid, String toUid) => '${fromUid}_$toUid';

  String pairId(String uidA, String uidB) =>
      uidA.compareTo(uidB) < 0 ? '${uidA}_$uidB' : '${uidB}_$uidA';

  Stream<List<FriendRequest>> watchIncomingRequests(String uid) {
    return _requests
        .where('toUid', isEqualTo: uid)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(FriendRequest.fromFirestore).toList());
  }

  Stream<List<FriendRequest>> watchOutgoingRequests(String uid) {
    return _requests
        .where('fromUid', isEqualTo: uid)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(FriendRequest.fromFirestore).toList());
  }

  /// Emittiert die uids aller Freunde des übergebenen Users.
  Stream<List<String>> watchFriendUids(String uid) {
    return _friendships.where('uids', arrayContains: uid).snapshots().map(
          (snapshot) => snapshot.docs
              .map((doc) => (doc.data()['uids'] as List).cast<String>())
              .map((uids) => uids.firstWhere((u) => u != uid))
              .toList(),
        );
  }

  Future<bool> areFriends(String uidA, String uidB) async {
    final doc = await _friendships.doc(pairId(uidA, uidB)).get();
    return doc.exists;
  }

  Future<bool> requestExists({required String fromUid, required String toUid}) async {
    final doc = await _requests.doc(_requestId(fromUid, toUid)).get();
    return doc.exists;
  }

  /// Sendet eine Freundschaftsanfrage. Wirft eine [FriendActionException],
  /// wenn beide bereits befreundet sind oder die Anfrage bereits existiert -
  /// die Firestore Security Rules erzwingen dasselbe zusätzlich serverseitig.
  Future<void> sendFriendRequest({required String fromUid, required String toUid}) async {
    if (fromUid == toUid) {
      throw const FriendActionException('Du kannst dich nicht selbst hinzufügen.');
    }
    if (await areFriends(fromUid, toUid)) {
      throw const FriendActionException('Ihr seid bereits befreundet.');
    }
    if (await requestExists(fromUid: fromUid, toUid: toUid)) {
      throw const FriendActionException('Die Anfrage wurde bereits gesendet.');
    }

    final request = FriendRequest(
      id: _requestId(fromUid, toUid),
      fromUid: fromUid,
      toUid: toUid,
      createdAt: DateTime.now(),
    );
    await _requests.doc(request.id).set(request.toFirestore());
  }

  /// Nimmt eine eingehende Anfrage an. Legt atomar die Freundschaft an und
  /// entfernt die Anfrage (inkl. einer eventuellen Gegenanfrage) in einem
  /// einzigen Batch - beide Schreibvorgänge gelingen oder scheitern gemeinsam.
  Future<void> acceptRequest({required String fromUid, required String toUid}) async {
    final batch = _firestore.batch();
    batch.set(_friendships.doc(pairId(fromUid, toUid)), {
      'uids': [fromUid, toUid],
      'createdAt': Timestamp.fromDate(DateTime.now()),
    });
    batch.delete(_requests.doc(_requestId(fromUid, toUid)));
    batch.delete(_requests.doc(_requestId(toUid, fromUid)));
    await batch.commit();
  }

  /// Lehnt eine Anfrage ab (oder nimmt eine selbst gesendete Anfrage zurück).
  Future<void> declineRequest({required String fromUid, required String toUid}) {
    return _requests.doc(_requestId(fromUid, toUid)).delete();
  }

  Future<void> removeFriend(String uidA, String uidB) {
    return _friendships.doc(pairId(uidA, uidB)).delete();
  }
}
