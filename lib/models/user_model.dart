import 'package:cloud_firestore/cloud_firestore.dart';

/// Repräsentiert das Firestore-Dokument `users/{uid}` eines Nutzers.
class AppUser {
  const AppUser({
    required this.uid,
    required this.name,
    required this.email,
    required this.friendCode,
    required this.createdAt,
    this.profilePicture,
    this.onboardingCompleted = false,
  });

  final String uid;
  final String name;
  final String email;
  final String? profilePicture;
  final String friendCode;
  final DateTime createdAt;

  /// Ob der Nutzer das Onboarding-Tutorial (3 Overlay-Hinweise zu den
  /// Swipe-Richtungen und dem Freundescode, siehe `OnboardingScreen`)
  /// bereits gesehen hat. Serverseitig auf `users/{uid}` gespeichert statt
  /// nur lokal auf dem Gerät, damit es bei einem Login auf einem neuen
  /// Gerät nicht erneut erscheint.
  final bool onboardingCompleted;

  factory AppUser.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    final createdAtValue = data['created_at'];
    return AppUser(
      uid: data['uid'] as String? ?? doc.id,
      name: data['name'] as String? ?? '',
      email: data['email'] as String? ?? '',
      profilePicture: data['profile_picture'] as String?,
      friendCode: data['friend_code'] as String? ?? '',
      createdAt: createdAtValue is Timestamp
          ? createdAtValue.toDate()
          : DateTime.now(),
      onboardingCompleted: data['onboarding_completed'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'uid': uid,
      'name': name,
      'email': email,
      'profile_picture': profilePicture,
      'friend_code': friendCode,
      'created_at': Timestamp.fromDate(createdAt),
      'onboarding_completed': onboardingCompleted,
    };
  }
}
