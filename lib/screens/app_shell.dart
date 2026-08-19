import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/navigation_provider.dart';
import 'chat/chat_screen.dart';
import 'groups/groups_screen.dart';
import 'matches/matches_screen.dart';
import 'profile/profile_screen.dart';
import 'swipe/swipe_screen.dart';

/// Enthält die fünf Hauptbereiche der App und die untere Navigation
/// (Swipe | Matches | Gruppen | Chat | Profil).
class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  static const _screens = [
    SwipeScreen(),
    MatchesScreen(),
    GroupsScreen(),
    ChatScreen(),
    ProfileScreen(),
  ];

  static const _destinations = [
    NavigationDestination(icon: Icon(Icons.movie_outlined), selectedIcon: Icon(Icons.movie), label: 'Swipe'),
    NavigationDestination(icon: Icon(Icons.favorite_border), selectedIcon: Icon(Icons.favorite), label: 'Matches'),
    NavigationDestination(icon: Icon(Icons.group_outlined), selectedIcon: Icon(Icons.group), label: 'Gruppen'),
    NavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat_bubble), label: 'Chat'),
    NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profil'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedIndex = ref.watch(selectedTabIndexProvider);

    return Scaffold(
      body: IndexedStack(index: selectedIndex, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) =>
            ref.read(selectedTabIndexProvider.notifier).select(index),
        destinations: _destinations,
      ),
    );
  }
}
