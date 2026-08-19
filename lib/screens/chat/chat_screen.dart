import 'package:flutter/material.dart';

/// Gruppenchat. Nachrichtenliste, Eingabe und Firestore-Anbindung folgen
/// in einem eigenen Entwicklungsschritt.
class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chat')),
      body: const Center(
        child: Text('Chat-Bereich'),
      ),
    );
  }
}
