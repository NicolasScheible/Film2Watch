import 'package:cloud_firestore/cloud_firestore.dart';

/// Eine offene Gruppeneinladung (`group_invitations/{groupId}_{inviteeUid}`).
class GroupInvitation {
  const GroupInvitation({
    required this.id,
    required this.groupId,
    required this.inviterUid,
    required this.inviteeUid,
    required this.createdAt,
  });

  final String id;
  final String groupId;
  final String inviterUid;
  final String inviteeUid;
  final DateTime createdAt;

  factory GroupInvitation.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    final createdAtValue = data['createdAt'];
    return GroupInvitation(
      id: doc.id,
      groupId: data['groupId'] as String? ?? '',
      inviterUid: data['inviterUid'] as String? ?? '',
      inviteeUid: data['inviteeUid'] as String? ?? '',
      createdAt: createdAtValue is Timestamp ? createdAtValue.toDate() : DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'groupId': groupId,
      'inviterUid': inviterUid,
      'inviteeUid': inviteeUid,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
