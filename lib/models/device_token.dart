import 'package:cloud_firestore/cloud_firestore.dart';

enum DevicePlatform {
  android,
  ios;

  static DevicePlatform fromString(String value) {
    return DevicePlatform.values.firstWhere(
      (platform) => platform.name == value,
      orElse: () => DevicePlatform.android,
    );
  }
}

/// Ein FCM-Gerät eines Users (`users/{uid}/devices/{token}`). Dokument-ID ist
/// deterministisch der Token selbst - ein Gerät kann so strukturell nie
/// doppelt registriert werden, und ein Token-Refresh ist einfach "neues
/// Dokument für den neuen Token, altes Dokument entfernen" statt eines
/// fehleranfälligen In-Place-Updates des Token-Werts.
class DeviceToken {
  const DeviceToken({
    required this.token,
    required this.platform,
    required this.createdAt,
    required this.updatedAt,
  });

  final String token;
  final DevicePlatform platform;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory DeviceToken.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    final createdAtValue = data['created_at'];
    final updatedAtValue = data['updated_at'];
    return DeviceToken(
      token: data['token'] as String? ?? doc.id,
      platform: DevicePlatform.fromString(data['platform'] as String? ?? 'android'),
      createdAt: createdAtValue is Timestamp ? createdAtValue.toDate() : DateTime.now(),
      updatedAt: updatedAtValue is Timestamp ? updatedAtValue.toDate() : DateTime.now(),
    );
  }
}
