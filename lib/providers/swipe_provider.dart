import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/movie_swipe.dart';
import '../repositories/premium_repository.dart';
import '../repositories/swipe_repository.dart';
import '../repositories/user_preferences_repository.dart';
import '../services/swipe_service.dart';
import 'auth_provider.dart';
import 'group_provider.dart';

final swipeRepositoryProvider = Provider<SwipeRepository>((ref) {
  return SwipeRepository(ref.watch(firestoreProvider));
});

/// Serverseitig gepflegter Premium-Status des aktuellen Users (§15) -
/// ausschließlich lesend, siehe `PremiumRepository`.
final premiumRepositoryProvider = Provider<PremiumRepository>((ref) {
  return PremiumRepository(ref.watch(firestoreProvider));
});

final swipeServiceProvider = Provider<SwipeService>((ref) {
  return SwipeService(
    ref.watch(swipeRepositoryProvider),
    ref.watch(groupRepositoryProvider),
    ref.watch(premiumRepositoryProvider),
  );
});

/// Serverseitig gepflegte Genre-Präferenzen des aktuellen Users (§7/§18/
/// §17.4), Grundlage für den Genre-Bonus und Anti-Boost im Boost-Score
/// (`lib/utils/boost.dart`).
final userPreferencesRepositoryProvider = Provider<UserPreferencesRepository>((ref) {
  return UserPreferencesRepository(ref.watch(firestoreProvider));
});

/// Ein Film, den mindestens ein aktuelles Mitglied der Gruppe auf die
/// Watchlist ("Vielleicht später") gesetzt hat, zusammen mit den UIDs der
/// aktuellen Mitglieder, die ihn vorgemerkt haben.
class WatchlistEntry {
  const WatchlistEntry({
    required this.movieId,
    required this.memberUids,
    required this.updatedAt,
  });

  final int movieId;
  final List<String> memberUids;
  final DateTime updatedAt;
}

/// Rohe Watchlist-Swipes aller (auch ehemaliger) Mitglieder dieser Gruppe,
/// in Echtzeit - Grundlage für [groupWatchlistProvider], das die Filterung
/// auf aktuelle Mitglieder übernimmt. Öffentlich (nicht privat), damit
/// Tests diesen Stream analog zu `groupMatchesProvider` gezielt "vorwärmen"
/// können, bevor sie den kombinierten [groupWatchlistProvider] lesen.
final groupWatchlistSwipesProvider = StreamProvider.family<List<MovieSwipe>, String>((
  ref,
  groupId,
) {
  return ref.watch(swipeRepositoryProvider).watchWatchlist(groupId);
});

/// Die gruppenweit abgeglichene Watchlist: ein Eintrag pro Film, den
/// mindestens ein *aktuelles* Mitglied vorgemerkt hat, zuletzt aktualisiert
/// zuerst. Kombiniert reaktiv die rohen Watchlist-Swipes mit der aktuellen
/// Mitgliederliste (`groupMembersProvider`) - Einträge ehemaliger Mitglieder
/// werden herausgefiltert, analog zur bestehenden Match-Erkennung
/// (`functions/matchEngine.js`), die ebenfalls nur aktuelle Mitglieder
/// zählt. Ein einzelnes noch ladendes Mitglieder-Stream blockiert nicht die
/// ganze Liste (wird währenddessen einfach als "noch keine Mitglieder"
/// behandelt, bis die eigene Aktualisierung eintrifft) - analog zu
/// `allMyMatchesProvider`.
final groupWatchlistProvider = Provider.family<AsyncValue<List<WatchlistEntry>>, String>((
  ref,
  groupId,
) {
  final swipesAsync = ref.watch(groupWatchlistSwipesProvider(groupId));
  final currentMemberUids =
      ref.watch(groupMembersProvider(groupId)).value?.map((m) => m.uid).toSet() ??
          const <String>{};

  return swipesAsync.whenData((swipes) {
    final byMovie = <int, List<MovieSwipe>>{};
    for (final swipe in swipes) {
      if (!currentMemberUids.contains(swipe.uid)) continue;
      byMovie.putIfAbsent(swipe.movieId, () => []).add(swipe);
    }

    final entries = byMovie.entries.map((entry) {
      final memberUids = entry.value.map((s) => s.uid).toList()..sort();
      final updatedAt = entry.value.map((s) => s.updatedAt).reduce(
            (a, b) => a.isAfter(b) ? a : b,
          );
      return WatchlistEntry(movieId: entry.key, memberUids: memberUids, updatedAt: updatedAt);
    }).toList();

    entries.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return entries;
  });
});
