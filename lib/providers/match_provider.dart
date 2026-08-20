import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/movie_match.dart';
import '../repositories/match_repository.dart';
import 'auth_provider.dart';

/// Kein `match_service.dart`: es gibt keine Schreib-/Orchestrierungslogik
/// client-seitig zu kapseln (Matches entstehen ausschließlich serverseitig,
/// siehe `MatchRepository`) - analog zu `groupProvider`/`groupMembersProvider`,
/// die ebenfalls direkt auf `GroupRepository` zugreifen, statt eine leere
/// Zwischenschicht einzuziehen.
final matchRepositoryProvider = Provider<MatchRepository>((ref) {
  return MatchRepository(ref.watch(firestoreProvider));
});

/// Alle Matches einer Gruppe in Echtzeit, neueste zuerst.
final groupMatchesProvider = StreamProvider.family<List<MovieMatch>, String>((ref, groupId) {
  return ref.watch(matchRepositoryProvider).watchMatches(groupId);
});
