import 'package:flutter/material.dart';

import 'navigation/notification_navigator.dart';
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
      // Ermöglicht Navigation von außerhalb des Widget-Baums beim Tippen
      // einer Push-Notification (siehe `navigation/notification_navigator.dart`).
      navigatorKey: rootNavigatorKey,
      home: const AppGate(),
    );
  }
}
