import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user_statistics.dart';
import 'auth_provider.dart';
import 'match_provider.dart';
import 'swipe_provider.dart';

/// Persönliche Statistik-Ansicht (§15: "Detaillierte Statistiken",
/// Premium-Feature) - **mit dem Produktverantwortlichen abgestimmt**:
/// einfache Kennzahlen ausschließlich aus bereits vorhandenen Daten, keine
/// neue Tracking-Infrastruktur. Kombiniert die gruppenübergreifende
/// Swipe-Historie (`SwipeRepository.getAllSwipesForUser`), die bereits
/// serverseitig vorberechneten Genre-Präferenzen
/// (`UserPreferencesRepository`) und die bereits bestehende,
/// gruppenübergreifende Match-Liste (`allMyMatchesProvider`, identisch zum
/// globalen "Matches"-Tab). Rein lesend - keine dieser drei Quellen benötigt
/// eine neue Firestore-Berechtigung: alle drei sind schon heute für jeden
/// eingeloggten User (Free wie Premium) lesbar; das Premium-Gating dieser
/// Statistik-Ansicht ist ausschließlich ein Produkt-/UI-Entscheid (siehe
/// `StatisticsScreen`), analog zur Plattform-Mehrfachauswahl im Filter (§10/
/// §15).
///
/// `false`/leer, solange kein User eingeloggt ist - kein Fehler, kein
/// künstlicher Platzhalterwert.
final userStatisticsProvider = FutureProvider<UserStatistics>((ref) async {
  final uid = ref.watch(authStateChangesProvider).value?.uid;
  if (uid == null) return UserStatistics.empty;

  final matchCount = ref.watch(allMyMatchesProvider).value?.length ?? 0;
  final swipes = await ref.watch(swipeRepositoryProvider).getAllSwipesForUser(uid);
  final genrePreferences = await ref.watch(userPreferencesRepositoryProvider).getPreferences(uid);

  return UserStatistics.fromSwipes(
    swipes: swipes,
    matchCount: matchCount,
    genrePreferences: genrePreferences,
  );
});
