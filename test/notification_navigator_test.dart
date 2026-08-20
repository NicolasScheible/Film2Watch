import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:film2watch/navigation/notification_navigator.dart';
import 'package:film2watch/providers/auth_provider.dart';
import 'package:film2watch/repositories/group_repository.dart';
import 'package:film2watch/screens/groups/group_chat_screen.dart';
import 'package:film2watch/screens/groups/group_detail_screen.dart';
import 'package:film2watch/screens/groups/group_invitations_screen.dart';
import 'package:film2watch/screens/profile/friend_requests_screen.dart';
import 'package:film2watch/utils/notification_payload.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('navigateForNotification (9. Notification-Tap-Navigation)', () {
    late FakeFirebaseFirestore firestore;
    late String groupId;

    setUp(() async {
      firestore = FakeFirebaseFirestore();
      final group = await GroupRepository(firestore).createGroup(
        name: 'Filmabend',
        creatorUid: 'alice',
      );
      groupId = group.id;
    });

    Future<void> pumpBase(WidgetTester tester) async {
      final auth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'alice', email: 'alice@film2watch.app'),
        signedIn: true,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firebaseAuthProvider.overrideWithValue(auth),
            firestoreProvider.overrideWithValue(firestore),
          ],
          child: MaterialApp(
            navigatorKey: rootNavigatorKey,
            home: const Scaffold(body: SizedBox(key: Key('base'))),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('friend_request navigiert zu den Freundesanfragen', (tester) async {
      await pumpBase(tester);
      navigateForNotification(const NotificationPayload(type: NotificationType.friendRequest));
      await tester.pumpAndSettle();
      expect(find.byType(FriendRequestsScreen), findsOneWidget);
    });

    testWidgets('group_invitation navigiert zu den Gruppeneinladungen', (tester) async {
      await pumpBase(tester);
      navigateForNotification(const NotificationPayload(type: NotificationType.groupInvitation));
      await tester.pumpAndSettle();
      expect(find.byType(GroupInvitationsScreen), findsOneWidget);
    });

    testWidgets('match navigiert zur Gruppe', (tester) async {
      await pumpBase(tester);
      navigateForNotification(NotificationPayload(type: NotificationType.match, groupId: groupId));
      await tester.pumpAndSettle();
      expect(find.byType(GroupDetailScreen), findsOneWidget);
    });

    testWidgets('chat_message navigiert zum Gruppenchat', (tester) async {
      await pumpBase(tester);
      navigateForNotification(
        NotificationPayload(type: NotificationType.chatMessage, groupId: groupId),
      );
      await tester.pumpAndSettle();
      expect(find.byType(GroupChatScreen), findsOneWidget);
    });

    testWidgets('unknown navigiert nirgendwohin', (tester) async {
      await pumpBase(tester);
      navigateForNotification(const NotificationPayload(type: NotificationType.unknown));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('base')), findsOneWidget);
      expect(find.byType(FriendRequestsScreen), findsNothing);
    });
  });
}
