import 'package:flutter/material.dart';

/// Startbereich der App: Hier werden Nutzer künftig Filme swipen können.
/// Die Swipe-Mechanik (Kartenstapel, Gesten, Buttons) folgt in einem
/// eigenen, kontrollierten Entwicklungsschritt.
class SwipeScreen extends StatelessWidget {
  const SwipeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Swipe')),
      body: const Center(
        child: Text('Swipe-Bereich'),
      ),
    );
  }
}
