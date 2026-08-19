import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/friend_request.dart';
import '../models/public_profile.dart';
import '../repositories/friend_repository.dart';
import '../services/friend_service.dart';
import 'auth_provider.dart';

final friendRepositoryProvider = Provider<FriendRepository>((ref) {
  return FriendRepository(ref.watch(firestoreProvider));
});

final friendServiceProvider = Provider<FriendService>((ref) {
  return FriendService(
    ref.watch(friendRepositoryProvider),
    ref.watch(userRepositoryProvider),
  );
});

/// Öffentliches Profil eines beliebigen Users (Freund, Anfragen-Absender, ...).
final publicProfileProvider = StreamProvider.family<PublicProfile?, String>((ref, uid) {
  return ref.watch(userRepositoryProvider).watchPublicProfile(uid);
});

/// Eingehende Freundschaftsanfragen des aktuell eingeloggten Users.
final incomingFriendRequestsProvider = StreamProvider<List<FriendRequest>>((ref) {
  final uid = ref.watch(authStateChangesProvider).value?.uid;
  if (uid == null) return Stream.value(const []);
  return ref.watch(friendRepositoryProvider).watchIncomingRequests(uid);
});

/// Ausgehende Freundschaftsanfragen des aktuell eingeloggten Users.
final outgoingFriendRequestsProvider = StreamProvider<List<FriendRequest>>((ref) {
  final uid = ref.watch(authStateChangesProvider).value?.uid;
  if (uid == null) return Stream.value(const []);
  return ref.watch(friendRepositoryProvider).watchOutgoingRequests(uid);
});

/// Uids aller Freunde des aktuell eingeloggten Users.
final friendUidsProvider = StreamProvider<List<String>>((ref) {
  final uid = ref.watch(authStateChangesProvider).value?.uid;
  if (uid == null) return Stream.value(const []);
  return ref.watch(friendRepositoryProvider).watchFriendUids(uid);
});
