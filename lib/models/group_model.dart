import 'package:cloud_firestore/cloud_firestore.dart';

/// Eine Film2Watch-Gruppe (`groups/{groupId}`).
class Group {
  const Group({
    required this.id,
    required this.name,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.photoUrl,
  });

  final String id;
  final String name;
  final String? photoUrl;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Group.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    final createdAtValue = data['created_at'];
    final updatedAtValue = data['updated_at'];
    return Group(
      id: data['id'] as String? ?? doc.id,
      name: data['name'] as String? ?? '',
      photoUrl: data['photo_url'] as String?,
      createdBy: data['created_by'] as String? ?? '',
      createdAt: createdAtValue is Timestamp ? createdAtValue.toDate() : DateTime.now(),
      updatedAt: updatedAtValue is Timestamp ? updatedAtValue.toDate() : DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'name': name,
      'photo_url': photoUrl,
      'created_by': createdBy,
      'created_at': Timestamp.fromDate(createdAt),
      'updated_at': Timestamp.fromDate(updatedAt),
    };
  }
}
