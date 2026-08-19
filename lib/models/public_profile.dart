import 'package:cloud_firestore/cloud_firestore.dart';

/// Öffentlich sichtbare Teilmenge eines User-Profils
/// (`public_profiles/{uid}`), lesbar für jeden authentifizierten Nutzer.
/// Enthält bewusst keine privaten Daten wie die E-Mail-Adresse.
class PublicProfile {
  const PublicProfile({
    required this.uid,
    required this.name,
    required this.friendCode,
    this.profilePicture,
  });

  final String uid;
  final String name;
  final String? profilePicture;
  final String friendCode;

  factory PublicProfile.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return PublicProfile(
      uid: data['uid'] as String? ?? doc.id,
      name: data['name'] as String? ?? '',
      profilePicture: data['profile_picture'] as String?,
      friendCode: data['friend_code'] as String? ?? '',
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'uid': uid,
      'name': name,
      'profile_picture': profilePicture,
      'friend_code': friendCode,
    };
  }
}
