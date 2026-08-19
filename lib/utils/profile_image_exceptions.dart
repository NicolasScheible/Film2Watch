/// Wird geworfen, wenn ein Profilbild aus fachlichen Gründen nicht
/// hochgeladen werden kann (ungültiges Format, zu groß, Datei nicht
/// gefunden, keine Berechtigung). Kein technischer Firebase-Fehler.
class ProfileImageException implements Exception {
  const ProfileImageException(this.message);

  final String message;

  @override
  String toString() => 'ProfileImageException: $message';
}
