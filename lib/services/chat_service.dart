import '../repositories/chat_repository.dart';
import '../repositories/group_repository.dart';
import '../utils/chat_exceptions.dart';

/// Maximale Nachrichtenlänge - client- UND security-rule-seitig identisch
/// erzwungen (siehe `firestore.rules`, Kommentar bei `messages/{messageId}`).
const chatMaxMessageLength = 2000;

/// Orchestriert das Senden von Chat-Nachrichten. Prüft Mitgliedschaft und
/// Nachrichtentext, bevor überhaupt geschrieben wird (die Firestore Rules
/// erzwingen dieselben Prüfungen zusätzlich serverseitig).
class ChatService {
  ChatService(this._chatRepository, this._groupRepository);

  final ChatRepository _chatRepository;
  final GroupRepository _groupRepository;

  Future<void> sendMessage({
    required String groupId,
    required String senderUid,
    required String text,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw const ChatActionException('Nachricht darf nicht leer sein.');
    }
    if (trimmed.length > chatMaxMessageLength) {
      throw const ChatActionException(
        'Nachricht ist zu lang (maximal $chatMaxMessageLength Zeichen).',
      );
    }

    final member = await _groupRepository.getMember(groupId, senderUid);
    if (member == null) {
      throw const ChatActionException('Du bist kein Mitglied dieser Gruppe.');
    }

    await _chatRepository.sendMessage(groupId: groupId, senderUid: senderUid, text: trimmed);
  }
}
