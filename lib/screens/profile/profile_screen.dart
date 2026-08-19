import 'package:flutter/material.dart';

/// Profilbereich. Anzeige von Nutzerdaten, Freundesliste, Statistiken und
/// Einstellungen folgt, sobald Firebase Authentication angebunden ist.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profil')),
      body: const Center(
        child: Text('Profil-Bereich'),
      ),
    );
  }
}
