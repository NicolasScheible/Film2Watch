/// Client-seitige Validierung für die Auth-Formulare. Ersetzt keine
/// serverseitige Validierung durch Firebase, verhindert aber unnötige
/// Firebase-Aufrufe mit offensichtlich ungültigen Eingaben.
abstract final class AuthValidators {
  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  static String? name(String? value) {
    if ((value ?? '').trim().isEmpty) return 'Bitte gib deinen Namen ein.';
    return null;
  }

  static String? email(String? value) {
    final trimmed = (value ?? '').trim();
    if (trimmed.isEmpty) return 'Bitte gib deine E-Mail-Adresse ein.';
    if (!_emailPattern.hasMatch(trimmed)) {
      return 'Bitte gib eine gültige E-Mail-Adresse ein.';
    }
    return null;
  }

  static String? password(String? value) {
    final input = value ?? '';
    if (input.isEmpty) return 'Bitte gib ein Passwort ein.';
    if (input.length < 6) {
      return 'Das Passwort muss mindestens 6 Zeichen lang sein.';
    }
    return null;
  }

  static String? passwordConfirmation(String password, String? confirmation) {
    final input = confirmation ?? '';
    if (input.isEmpty) return 'Bitte bestätige dein Passwort.';
    if (password != input) return 'Die Passwörter stimmen nicht überein.';
    return null;
  }
}
