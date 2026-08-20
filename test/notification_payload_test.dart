import 'package:film2watch/utils/notification_payload.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NotificationPayload.fromData', () {
    test('6a. friend_request wird korrekt geparst', () {
      final payload = NotificationPayload.fromData({'type': 'friend_request'});
      expect(payload.type, NotificationType.friendRequest);
    });

    test('6b. group_invitation wird korrekt geparst', () {
      final payload = NotificationPayload.fromData({
        'type': 'group_invitation',
        'group_id': 'g1',
      });
      expect(payload.type, NotificationType.groupInvitation);
      expect(payload.groupId, 'g1');
    });

    test('6c. match wird korrekt geparst', () {
      final payload = NotificationPayload.fromData({'type': 'match', 'group_id': 'g1'});
      expect(payload.type, NotificationType.match);
      expect(payload.groupId, 'g1');
    });

    test('6d. chat_message wird korrekt geparst', () {
      final payload = NotificationPayload.fromData({
        'type': 'chat_message',
        'group_id': 'g1',
      });
      expect(payload.type, NotificationType.chatMessage);
      expect(payload.groupId, 'g1');
    });

    test('10a. ungültiger Payload (fehlendes type-Feld) ergibt unknown statt Absturz', () {
      final payload = NotificationPayload.fromData(<String, dynamic>{});
      expect(payload.type, NotificationType.unknown);
    });

    test('10b. ungültiger Payload (group_id fehlt bei group_invitation) ergibt unknown', () {
      final payload = NotificationPayload.fromData({'type': 'group_invitation'});
      expect(payload.type, NotificationType.unknown);
    });

    test('10c. ungültiger Payload (group_id ist leer) ergibt unknown', () {
      final payload = NotificationPayload.fromData({'type': 'match', 'group_id': ''});
      expect(payload.type, NotificationType.unknown);
    });

    test('10d. ungültiger Payload (type ist kein String) ergibt unknown', () {
      final payload = NotificationPayload.fromData({'type': 42});
      expect(payload.type, NotificationType.unknown);
    });

    test('11. unbekannter Notification-Typ ergibt unknown', () {
      final payload = NotificationPayload.fromData({'type': 'irgendwas_neues'});
      expect(payload.type, NotificationType.unknown);
    });
  });
}
