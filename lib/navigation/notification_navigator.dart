import 'package:flutter/material.dart';

import '../screens/groups/group_chat_screen.dart';
import '../screens/groups/group_detail_screen.dart';
import '../screens/groups/group_invitations_screen.dart';
import '../screens/profile/friend_requests_screen.dart';
import '../utils/notification_payload.dart';

/// Globaler Navigator-Key auf dem bestehenden `MaterialApp` (siehe
/// `app.dart`) - ermöglicht Navigation von außerhalb des Widget-Baums (aus
/// dem FCM-Tap-Handler heraus, der keinen eigenen `BuildContext` hat), ohne
/// eine neue, parallele Navigations-Architektur einzuführen.
final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Navigiert zum passenden Ziel für eine getippte Notification. Wird sowohl
/// vom FCM-Tap-Handler (Hintergrund/Terminated) als auch vom Tap auf die
/// lokale Vordergrund-Notification aufgerufen - exakt derselbe Code-Pfad,
/// keine doppelte Navigations-Logik.
void navigateForNotification(NotificationPayload payload) {
  final navigator = rootNavigatorKey.currentState;
  if (navigator == null) return;

  switch (payload.type) {
    case NotificationType.friendRequest:
      navigator.push(MaterialPageRoute(builder: (_) => const FriendRequestsScreen()));
    case NotificationType.groupInvitation:
      navigator.push(MaterialPageRoute(builder: (_) => const GroupInvitationsScreen()));
    case NotificationType.match:
      final groupId = payload.groupId;
      if (groupId != null) {
        navigator.push(MaterialPageRoute(builder: (_) => GroupDetailScreen(groupId: groupId)));
      }
    case NotificationType.chatMessage:
      final groupId = payload.groupId;
      if (groupId != null) {
        navigator.push(MaterialPageRoute(builder: (_) => GroupChatScreen(groupId: groupId)));
      }
    case NotificationType.movieNight:
      final groupId = payload.groupId;
      if (groupId != null) {
        navigator.push(MaterialPageRoute(builder: (_) => GroupDetailScreen(groupId: groupId)));
      }
    case NotificationType.unknown:
      break;
  }
}
