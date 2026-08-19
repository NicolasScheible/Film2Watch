/// Validierung für Gruppen-Formulare.
abstract final class GroupValidators {
  static const minNameLength = 2;
  static const maxNameLength = 50;

  static String? name(String? value) {
    final trimmed = (value ?? '').trim();
    if (trimmed.isEmpty) return 'Bitte gib einen Gruppennamen ein.';
    if (trimmed.length < minNameLength) {
      return 'Der Gruppenname muss mindestens $minNameLength Zeichen lang sein.';
    }
    if (trimmed.length > maxNameLength) {
      return 'Der Gruppenname darf höchstens $maxNameLength Zeichen lang sein.';
    }
    return null;
  }
}
