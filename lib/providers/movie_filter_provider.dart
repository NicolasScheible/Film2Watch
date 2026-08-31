import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/movie_filter.dart';

/// Hält den aktuell aktiven [MovieFilter] für die Swipe-Session einer
/// Gruppe. Bewusst rein session-lokaler `Notifier`-State (kein Firestore,
/// keine Persistenz) - die Master-Spezifikation verlangt an keiner Stelle
/// eine dauerhafte Speicherung der Filterauswahl. Family-Provider pro
/// `groupId` (Konstruktor-Parameter, analog zu `SwipeActionController`),
/// damit ein Filterwechsel in einer Gruppe niemals die Swipe-Session einer
/// anderen Gruppe beeinflusst.
class MovieFilterController extends Notifier<MovieFilter> {
  MovieFilterController(this.groupId);

  final String groupId;

  @override
  MovieFilter build() => MovieFilter.empty;

  void update(MovieFilter filter) => state = filter;

  void clear() => state = MovieFilter.empty;
}

final movieFilterControllerProvider =
    NotifierProvider.family<MovieFilterController, MovieFilter, String>(
  MovieFilterController.new,
);
