import 'package:flutter/material.dart';

/// Übersicht der Gruppen eines Nutzers. Erstellen/Beitreten von Gruppen
/// sowie die Firestore-Anbindung folgen in einem eigenen Entwicklungsschritt.
class GroupsScreen extends StatelessWidget {
  const GroupsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gruppen')),
      body: const Center(
        child: Text('Gruppen-Bereich'),
      ),
    );
  }
}
