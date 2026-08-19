import 'package:cloud_firestore/cloud_firestore.dart';

enum GroupRole {
  admin,
  member;

  static GroupRole fromString(String value) {
    return GroupRole.values.firstWhere(
      (role) => role.name == value,
      orElse: () => GroupRole.member,
    );
  }
}

/// Mitgliedschaft eines Users in einer Gruppe (`groups/{groupId}/members/{uid}`).
class GroupMember {
  const GroupMember({
    required this.uid,
    required this.role,
    required this.joinedAt,
  });

  final String uid;
  final GroupRole role;
  final DateTime joinedAt;

  bool get isAdmin => role == GroupRole.admin;

  factory GroupMember.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    final joinedAtValue = data['joined_at'];
    return GroupMember(
      uid: data['uid'] as String? ?? doc.id,
      role: GroupRole.fromString(data['role'] as String? ?? 'member'),
      joinedAt: joinedAtValue is Timestamp ? joinedAtValue.toDate() : DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'uid': uid,
      'role': role.name,
      'joined_at': Timestamp.fromDate(joinedAt),
    };
  }
}
