import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_provider.dart';
import 'group_provider.dart';

/// Steuert alle mutierenden Gruppen-Aktionen (umbenennen, Bild ändern/
/// entfernen, einladen, annehmen/ablehnen, Mitglied entfernen, Admin
/// übertragen, verlassen, löschen). Verhindert per [AsyncValue.isLoading]
/// mehrfaches Auslösen derselben Aktion.
class GroupActionController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  String? get _uid => ref.read(authStateChangesProvider).value?.uid;

  Future<void> _run(Future<void> Function() action) async {
    if (state.isLoading) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(action);
  }

  Future<void> renameGroup(String groupId, String name) async {
    final uid = _uid;
    if (uid == null) return;
    await _run(() => ref
        .read(groupServiceProvider)
        .renameGroup(groupId: groupId, callerUid: uid, name: name));
  }

  Future<void> uploadGroupImage(String groupId, File file) async {
    final uid = _uid;
    if (uid == null) return;
    await _run(() => ref
        .read(groupServiceProvider)
        .uploadGroupImage(groupId: groupId, callerUid: uid, file: file));
  }

  Future<void> removeGroupImage(String groupId) async {
    final uid = _uid;
    if (uid == null) return;
    await _run(
      () => ref.read(groupServiceProvider).removeGroupImage(groupId: groupId, callerUid: uid),
    );
  }

  Future<void> inviteFriend(String groupId, String inviteeUid) async {
    final uid = _uid;
    if (uid == null) return;
    await _run(() => ref
        .read(groupServiceProvider)
        .inviteFriend(groupId: groupId, inviterUid: uid, inviteeUid: inviteeUid));
  }

  Future<void> acceptInvitation(String groupId) async {
    final uid = _uid;
    if (uid == null) return;
    await _run(
      () => ref.read(groupServiceProvider).acceptInvitation(groupId: groupId, inviteeUid: uid),
    );
  }

  Future<void> declineInvitation(String groupId) async {
    final uid = _uid;
    if (uid == null) return;
    await _run(
      () => ref.read(groupServiceProvider).declineInvitation(groupId: groupId, inviteeUid: uid),
    );
  }

  Future<void> removeMember(String groupId, String targetUid) async {
    final uid = _uid;
    if (uid == null) return;
    await _run(() => ref
        .read(groupServiceProvider)
        .removeMember(groupId: groupId, callerUid: uid, targetUid: targetUid));
  }

  Future<void> transferAdmin(String groupId, String newAdminUid) async {
    final uid = _uid;
    if (uid == null) return;
    await _run(() => ref
        .read(groupServiceProvider)
        .transferAdmin(groupId: groupId, callerUid: uid, newAdminUid: newAdminUid));
  }

  Future<void> leaveGroup(String groupId) async {
    final uid = _uid;
    if (uid == null) return;
    await _run(() => ref.read(groupServiceProvider).leaveGroup(groupId: groupId, uid: uid));
  }

  Future<void> deleteGroup(String groupId) async {
    final uid = _uid;
    if (uid == null) return;
    await _run(
      () => ref.read(groupServiceProvider).deleteGroup(groupId: groupId, callerUid: uid),
    );
  }
}

final groupActionControllerProvider =
    AsyncNotifierProvider<GroupActionController, void>(GroupActionController.new);
