import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Verwaltet den Index des aktuell ausgewählten Tabs in der Bottom-Navigation
/// (Swipe | Matches | Gruppen | Chat | Profil).
class SelectedTabIndex extends Notifier<int> {
  @override
  int build() => 0;

  void select(int index) => state = index;
}

final selectedTabIndexProvider =
    NotifierProvider<SelectedTabIndex, int>(SelectedTabIndex.new);
