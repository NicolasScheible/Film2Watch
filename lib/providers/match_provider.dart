import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/group_model.dart';
import '../models/movie_match.dart';
import '../repositories/match_repository.dart';
import 'auth_provider.dart';
import 'group_provider.dart';

/// Kein `match_service.dart`: es gibt keine Schreib-/Orchestrierungslogik
/// client-seitig zu kapseln (Matches entstehen ausschließlich serverseitig,
/// siehe `MatchRepository`) - analog zu `groupProvider`/`groupMembersProvider`,
/// die ebenfalls direkt auf `GroupRepository` zugreifen, statt eine leere
/// Zwischenschicht einzuziehen. Die gruppenübergreifende Aggregation unten
/// (`allMyMatchesProvider`) ist reine Riverpod-Provider-Komposition (mehrere
/// bereits bestehende Provider reaktiv kombinieren) - kein `ref` in einer
/// Service-Klasse verfügbar, gehört also ebenfalls in die Provider-Schicht,
/// nicht in einen Service.
final matchRepositoryProvider = Provider<MatchRepository>((ref) {
  return MatchRepository(ref.watch(firestoreProvider));
});

/// Alle Matches einer Gruppe in Echtzeit, neueste zuerst.
final groupMatchesProvider = StreamProvider.family<List<MovieMatch>, String>((
  ref,
  groupId,
) {
  return ref.watch(matchRepositoryProvider).watchMatches(groupId);
});

/// Ein Match zusammen mit der Gruppe, in der er entstanden ist - für die
/// gruppenübergreifende Match-Liste (globaler „Matches"-Tab).
class GroupMatch {
  const GroupMatch({required this.group, required this.match});

  final Group group;
  final MovieMatch match;
}

/// Alle Matches über alle Gruppen des aktuell eingeloggten Users hinweg,
/// neueste zuerst - kombiniert reaktiv `myGroupsProvider` mit je einem
/// `groupMatchesProvider(groupId)` pro Gruppe. Aktualisiert sich automatisch,
/// sobald sich die Gruppenliste ändert oder in irgendeiner Gruppe ein neues
/// Match entsteht. Ein einzelnes noch ladendes Gruppen-Match-Stream blockiert
/// nicht die ganze Liste (wird währenddessen einfach als "noch leer"
/// behandelt, bis die eigene Aktualisierung eintrifft).
final allMyMatchesProvider = Provider<AsyncValue<List<GroupMatch>>>((ref) {
  final groupsAsync = ref.watch(myGroupsProvider);

  return groupsAsync.whenData((groups) {
    final result = <GroupMatch>[];
    for (final group in groups) {
      final matches =
          ref.watch(groupMatchesProvider(group.id)).value ?? const [];
      for (final match in matches) {
        result.add(GroupMatch(group: group, match: match));
      }
    }
    result.sort((a, b) => b.match.matchedAt.compareTo(a.match.matchedAt));
    return result;
  });
});
