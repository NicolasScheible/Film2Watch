/// Wählt aus TMDBs Credits-Antwort (`/movie/{id}/credits`) die
/// Hauptdarsteller-IDs für den Cast-Anti-Boost (§7 der Master-Spezifikation:
/// "Ein Dislike senkt den Score ähnlicher Filme (gleiches Genre, gleicher
/// Hauptdarsteller) leicht (–10)"). "Hauptdarsteller" = die Top 3 Einträge
/// aus TMDBs bereits nach `order` sortiertem `cast`-Array (0 = am
/// prominentesten billed) - mit dem Produktverantwortlichen abgestimmt, da
/// die Master-Spezifikation selbst keine Zahl nennt, aber konsistent mit der
/// bereits bestehenden "Top-3-Genres"-Regel für die Genre-Präferenz im
/// selben Boost-System. Nur numerische TMDB-Personen-IDs - keine Namen,
/// keine Bilder, keine vollständigen Cast-Daten.
///
/// Robust gegen fehlende/unvollständige Daten: ein `cast`-Eintrag ohne
/// gültige `id`/`order` wird ignoriert statt die ganze Liste zu verwerfen;
/// fehlt `cast` komplett, ist das Ergebnis eine leere Liste (kein Fehler -
/// TMDB liefert für sehr wenige Filme keine Besetzungsdaten).
List<int> selectMainCastIds(Map<String, dynamic> json, {int limit = 3}) {
  final cast = json['cast'];
  if (cast is! List) return const [];

  final entries = <({int id, int order})>[];
  for (final entry in cast.whereType<Map<String, dynamic>>()) {
    final id = entry['id'];
    final order = entry['order'];
    if (id is! num || order is! num) continue;
    entries.add((id: id.toInt(), order: order.toInt()));
  }

  entries.sort((a, b) => a.order.compareTo(b.order));
  return entries.take(limit).map((e) => e.id).toList();
}
