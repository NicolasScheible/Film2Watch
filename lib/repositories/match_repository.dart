import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/movie_match.dart';

/// Rein lesender Firestore-Zugriff auf `groups/{groupId}/matches`. Es gibt
/// bewusst keine Schreibmethoden: Match-Dokumente entstehen ausschließlich
/// serverseitig über die Cloud Function `onSwipeWritten`
/// (`functions/index.js`) mit Admin-Rechten; die Firestore Security Rules
/// verbieten jedem Client jeglichen Schreibzugriff kategorisch
/// (`allow write: if false`). Ein Schreibpfad hier wäre also ohnehin
/// wirkungslos und würde nur eine nicht existierende Möglichkeit vortäuschen.
class MatchRepository {
  MatchRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _matches(String groupId) =>
      _firestore.collection('groups').doc(groupId).collection('matches');

  /// Alle Matches einer Gruppe, neueste zuerst - reagiert in Echtzeit auf
  /// neue, von der Cloud Function erzeugte Match-Dokumente.
  Stream<List<MovieMatch>> watchMatches(String groupId) {
    return _matches(groupId)
        .orderBy('matched_at', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(MovieMatch.fromFirestore).toList());
  }

  /// Prüft, ob [movieId] ein bestehendes Match dieser Gruppe ist - Grundlage
  /// für die Validierung des optionalen Filmabend-Films (§12: darf
  /// ausschließlich ein bereits gematchter Film sein, kein beliebiger
  /// TMDB-Film). Dokument-ID ist deterministisch die movieId (siehe
  /// `functions/matchEngine.js`).
  Future<bool> isMatch(String groupId, int movieId) async {
    final snapshot = await _matches(groupId).doc(movieId.toString()).get();
    return snapshot.exists;
  }
}
