/// Typ einer Push-Notification, abgeleitet aus dem `data`-Feld der
/// FCM-Nachricht (nie aus dem `notification`-Block, der nur für die reine
/// Anzeige gedacht ist).
enum NotificationType { friendRequest, groupInvitation, match, chatMessage, movieNight, unknown }

/// Getypte, geparste Darstellung des `data`-Payloads einer FCM-Nachricht.
/// FCM liefert `data` immer als `Map<String, String>` - dieser Parser ist
/// bewusst defensiv: ein fehlendes/unbekanntes `type` oder fehlende
/// Pflichtfelder ergeben [NotificationType.unknown] statt eines Absturzes.
class NotificationPayload {
  const NotificationPayload({required this.type, this.groupId});

  final NotificationType type;
  final String? groupId;

  factory NotificationPayload.fromData(Map<String, dynamic> data) {
    final type = data['type'];
    if (type is! String) return const NotificationPayload(type: NotificationType.unknown);

    switch (type) {
      case 'friend_request':
        return const NotificationPayload(type: NotificationType.friendRequest);
      case 'group_invitation':
        return _withGroupId(data, NotificationType.groupInvitation);
      case 'match':
        return _withGroupId(data, NotificationType.match);
      case 'chat_message':
        return _withGroupId(data, NotificationType.chatMessage);
      case 'movie_night':
        return _withGroupId(data, NotificationType.movieNight);
      default:
        return const NotificationPayload(type: NotificationType.unknown);
    }
  }

  static NotificationPayload _withGroupId(Map<String, dynamic> data, NotificationType type) {
    final groupId = data['group_id'];
    if (groupId is! String || groupId.isEmpty) {
      return const NotificationPayload(type: NotificationType.unknown);
    }
    return NotificationPayload(type: type, groupId: groupId);
  }
}
