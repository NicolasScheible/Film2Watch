import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/movie_night.dart';
import '../repositories/movie_night_repository.dart';
import '../services/movie_night_service.dart';
import 'auth_provider.dart';
import 'group_provider.dart';
import 'match_provider.dart';

final movieNightRepositoryProvider = Provider<MovieNightRepository>((ref) {
  return MovieNightRepository(ref.watch(firestoreProvider));
});

final movieNightServiceProvider = Provider<MovieNightService>((ref) {
  return MovieNightService(
    ref.watch(movieNightRepositoryProvider),
    ref.watch(groupRepositoryProvider),
    ref.watch(matchRepositoryProvider),
  );
});

/// Alle geplanten Filmabende einer Gruppe (§12), live, nächster Termin
/// zuerst.
final groupMovieNightsProvider = StreamProvider.family<List<MovieNight>, String>((
  ref,
  groupId,
) {
  return ref.watch(movieNightRepositoryProvider).watchMovieNights(groupId);
});
