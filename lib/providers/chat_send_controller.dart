import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_provider.dart';
import 'chat_provider.dart';

/// Sendet eine Chat-Nachricht. Verhindert per [AsyncValue.isLoading]
/// mehrfaches Auslösen durch schnelles Antippen des Senden-Buttons, während
/// ein Sendevorgang noch läuft.
class ChatSendController extends AsyncNotifier<void> {
  ChatSendController(this.groupId);

  final String groupId;

  @override
  Future<void> build() async {}

  Future<void> send(String text) async {
    final uid = ref.read(authStateChangesProvider).value?.uid;
    if (uid == null || state.isLoading) return;

    state = const AsyncLoading();
    state = await AsyncValue.guard(() {
      return ref.read(chatServiceProvider).sendMessage(
            groupId: groupId,
            senderUid: uid,
            text: text,
          );
    });
  }
}

final chatSendControllerProvider =
    AsyncNotifierProvider.family<ChatSendController, void, String>(
  ChatSendController.new,
);
