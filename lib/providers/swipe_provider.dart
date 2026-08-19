import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repositories/swipe_repository.dart';
import '../services/swipe_service.dart';
import 'auth_provider.dart';
import 'group_provider.dart';

final swipeRepositoryProvider = Provider<SwipeRepository>((ref) {
  return SwipeRepository(ref.watch(firestoreProvider));
});

final swipeServiceProvider = Provider<SwipeService>((ref) {
  return SwipeService(ref.watch(swipeRepositoryProvider), ref.watch(groupRepositoryProvider));
});
