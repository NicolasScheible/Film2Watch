import 'package:flutter/material.dart';

import 'screens/app_gate.dart';
import 'theme/app_theme.dart';

class Film2WatchApp extends StatelessWidget {
  const Film2WatchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Film2Watch',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      home: const AppGate(),
    );
  }
}
