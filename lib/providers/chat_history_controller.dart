import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/chat_message.dart';
import 'chat_provider.dart';

/// Hält die zusätzlich (manuell) nachgeladenen, älteren Nachrichten einer
/// Gruppe - getrennt vom Live-Fenster in [chatMessagesProvider]. Die Screen
/// verbindet beide Listen für die Anzeige. So bleibt das reaktive Live-
/// Fenster ein einfacher Firestore-Stream, während die (imperative)
/// Pagination unabhängig davon funktioniert.
class ChatHistoryController extends AsyncNotifier<List<ChatMessage>> {
  ChatHistoryController(this.groupId);

  final String groupId;

  @override
  Future<List<ChatMessage>> build() async => const [];

  /// Lädt eine weitere Seite Nachrichten vor [before] und stellt sie den
  /// bereits geladenen älteren Nachrichten voran.
  Future<void> loadOlder(DateTime before) async {
    if (state.isLoading) return;
    final current = state.value ?? const <ChatMessage>[];

    state = const AsyncLoading<List<ChatMessage>>();
    state = await AsyncValue.guard(() async {
      final older = await ref.read(chatRepositoryProvider).loadOlderMessages(groupId, before: before);
      return [...older, ...current];
    });
  }
}

final chatHistoryControllerProvider =
    AsyncNotifierProvider.family<ChatHistoryController, List<ChatMessage>, String>(
  ChatHistoryController.new,
);
