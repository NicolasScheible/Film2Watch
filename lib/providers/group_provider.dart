import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/group_invitation.dart';
import '../models/group_member.dart';
import '../models/group_model.dart';
import '../repositories/group_repository.dart';
import '../services/group_service.dart';
import 'auth_provider.dart';
import 'friend_provider.dart';
import 'storage_provider.dart';

final groupRepositoryProvider = Provider<GroupRepository>((ref) {
  return GroupRepository(ref.watch(firestoreProvider));
});

final groupServiceProvider = Provider<GroupService>((ref) {
  return GroupService(
    ref.watch(groupRepositoryProvider),
    ref.watch(friendRepositoryProvider),
    ref.watch(storageServiceProvider),
  );
});

/// Alle Gruppen des aktuell eingeloggten Users.
final myGroupsProvider = StreamProvider<List<Group>>((ref) {
  final uid = ref.watch(authStateChangesProvider).value?.uid;
  if (uid == null) return Stream.value(const []);
  return ref.watch(groupRepositoryProvider).watchMyGroups(uid);
});

final groupProvider = StreamProvider.family<Group?, String>((ref, groupId) {
  return ref.watch(groupRepositoryProvider).watchGroup(groupId);
});

final groupMembersProvider = StreamProvider.family<List<GroupMember>, String>((ref, groupId) {
  return ref.watch(groupRepositoryProvider).watchMembers(groupId);
});

/// Die eigene Mitgliedschaft (inkl. Rolle) in einer bestimmten Gruppe.
final myMembershipProvider = Provider.family<GroupMember?, String>((ref, groupId) {
  final uid = ref.watch(authStateChangesProvider).value?.uid;
  final members = ref.watch(groupMembersProvider(groupId)).value ?? const [];
  if (uid == null) return null;
  for (final member in members) {
    if (member.uid == uid) return member;
  }
  return null;
});

/// Eingehende Gruppeneinladungen des aktuell eingeloggten Users.
final incomingGroupInvitationsProvider = StreamProvider<List<GroupInvitation>>((ref) {
  final uid = ref.watch(authStateChangesProvider).value?.uid;
  if (uid == null) return Stream.value(const []);
  return ref.watch(groupRepositoryProvider).watchIncomingInvitations(uid);
});
