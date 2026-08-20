import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/chat_message.dart';
import '../repositories/chat_repository.dart';
import '../services/chat_service.dart';
import 'auth_provider.dart';
import 'group_provider.dart';

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  return ChatRepository(ref.watch(firestoreProvider));
});

final chatServiceProvider = Provider<ChatService>((ref) {
  return ChatService(ref.watch(chatRepositoryProvider), ref.watch(groupRepositoryProvider));
});

/// Live-Fenster der neuesten Nachrichten einer Gruppe, älteste zuerst - kein
/// unbegrenztes Laden der gesamten Historie. Ältere Nachrichten werden über
/// [chatHistoryControllerProvider] separat nachgeladen.
final chatMessagesProvider = StreamProvider.family<List<ChatMessage>, String>((ref, groupId) {
  return ref.watch(chatRepositoryProvider).watchLatestMessages(groupId);
});
