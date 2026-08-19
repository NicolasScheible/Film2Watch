import 'package:cloud_firestore/cloud_firestore.dart';

/// Eine offene Freundschaftsanfrage (`friend_requests/{fromUid}_{toUid}`).
class FriendRequest {
  const FriendRequest({
    required this.id,
    required this.fromUid,
    required this.toUid,
    required this.createdAt,
  });

  final String id;
  final String fromUid;
  final String toUid;
  final DateTime createdAt;

  factory FriendRequest.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    final createdAtValue = data['createdAt'];
    return FriendRequest(
      id: doc.id,
      fromUid: data['fromUid'] as String? ?? '',
      toUid: data['toUid'] as String? ?? '',
      createdAt: createdAtValue is Timestamp ? createdAtValue.toDate() : DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'fromUid': fromUid,
      'toUid': toUid,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
