import 'package:flutter/material.dart';

import '../movies/tmdb_browse_screen.dart';

/// Startbereich der App: Hier werden Nutzer künftig Filme swipen können.
/// Die Swipe-Mechanik (Kartenstapel, Gesten, Buttons) folgt in einem
/// eigenen, kontrollierten Entwicklungsschritt. Der Button unten öffnet
/// ausschließlich die technische Verifikationsseite der TMDB-Integration.
class SwipeScreen extends StatelessWidget {
  const SwipeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Swipe')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Swipe-Bereich'),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const TmdbBrowseScreen())),
              child: const Text('TMDB Test / Browse'),
            ),
          ],
        ),
      ),
    );
  }
}
