import 'package:flutter/material.dart';

/// Übersicht der Film-Matches. Die Anbindung an Firestore und die
/// tatsächliche Matching-Logik folgen in einem eigenen Entwicklungsschritt.
class MatchesScreen extends StatelessWidget {
  const MatchesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Matches')),
      body: const Center(
        child: Text('Matches-Bereich'),
      ),
    );
  }
}
