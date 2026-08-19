import 'dart:io';

import '../models/group_model.dart';
import '../repositories/friend_repository.dart';
import '../repositories/group_repository.dart';
import '../services/storage_service.dart';
import '../utils/group_exceptions.dart';
import '../utils/group_validators.dart';

/// Orchestriert das Gruppen-System. Die UI spricht ausschließlich mit diesem
/// Service, nie direkt mit Firestore/Storage.
class GroupService {
  GroupService(this._groupRepository, this._friendRepository, this._storageService);

  final GroupRepository _groupRepository;
  final FriendRepository _friendRepository;
  final StorageService _storageService;

  Future<Group> createGroup({required String name, required String creatorUid}) async {
    final validationError = GroupValidators.name(name);
    if (validationError != null) throw GroupActionException(validationError);
    return _groupRepository.createGroup(name: name.trim(), creatorUid: creatorUid);
  }

  Future<void> renameGroup({
    required String groupId,
    required String callerUid,
    required String name,
  }) async {
    final validationError = GroupValidators.name(name);
    if (validationError != null) throw GroupActionException(validationError);
    await _requireAdmin(groupId, callerUid);
    await _groupRepository.updateGroupName(groupId, name.trim());
  }

  Future<void> uploadGroupImage({
    required String groupId,
    required String callerUid,
    required File file,
  }) async {
    await _requireAdmin(groupId, callerUid);
    final url = await _storageService.uploadGroupImage(groupId: groupId, file: file);
    await _groupRepository.updateGroupPhoto(groupId, url);
  }

  Future<void> removeGroupImage({required String groupId, required String callerUid}) async {
    await _requireAdmin(groupId, callerUid);
    await _storageService.deleteGroupImage(groupId);
    await _groupRepository.updateGroupPhoto(groupId, null);
  }

  Future<void> inviteFriend({
    required String groupId,
    required String inviterUid,
    required String inviteeUid,
  }) async {
    await _requireAdmin(groupId, inviterUid);

    if (inviterUid == inviteeUid) {
      throw const GroupActionException('Du kannst dich nicht selbst einladen.');
    }
    if (!await _friendRepository.areFriends(inviterUid, inviteeUid)) {
      throw const GroupActionException('Du kannst nur Freunde in die Gruppe einladen.');
    }
    final existingMember = await _groupRepository.getMember(groupId, inviteeUid);
    if (existingMember != null) {
      throw const GroupActionException('Diese Person ist bereits Mitglied der Gruppe.');
    }
    if (await _groupRepository.invitationExists(groupId, inviteeUid)) {
      throw const GroupActionException('Diese Person wurde bereits eingeladen.');
    }

    await _groupRepository.createInvitation(
      groupId: groupId,
      inviterUid: inviterUid,
      inviteeUid: inviteeUid,
    );
  }

  Future<void> acceptInvitation({required String groupId, required String inviteeUid}) {
    return _groupRepository.acceptInvitation(groupId: groupId, inviteeUid: inviteeUid);
  }

  Future<void> declineInvitation({required String groupId, required String inviteeUid}) {
    return _groupRepository.declineInvitation(groupId: groupId, inviteeUid: inviteeUid);
  }

  Future<void> removeMember({
    required String groupId,
    required String callerUid,
    required String targetUid,
  }) async {
    await _requireAdmin(groupId, callerUid);
    if (callerUid == targetUid) {
      throw const GroupActionException(
        'Du kannst dich nicht selbst über „Mitglied entfernen" entfernen. Nutze stattdessen „Gruppe verlassen".',
      );
    }
    await _groupRepository.removeMember(groupId, targetUid);
  }

  Future<void> transferAdmin({
    required String groupId,
    required String callerUid,
    required String newAdminUid,
  }) async {
    await _requireAdmin(groupId, callerUid);
    if (callerUid == newAdminUid) {
      throw const GroupActionException('Du bist bereits Admin dieser Gruppe.');
    }
    final newAdmin = await _groupRepository.getMember(groupId, newAdminUid);
    if (newAdmin == null) {
      throw const GroupActionException('Diese Person ist kein Mitglied dieser Gruppe.');
    }
    await _groupRepository.transferAdmin(
      groupId: groupId,
      currentAdminUid: callerUid,
      newAdminUid: newAdminUid,
    );
  }

  /// Verlässt die Gruppe. Ein Admin muss vorher per [transferAdmin] einen
  /// neuen Admin bestimmen, sofern noch weitere Mitglieder vorhanden sind -
  /// ansonsten (letztes verbliebenes Mitglied) wird die Gruppe stattdessen
  /// vollständig gelöscht, um keine verwaiste Gruppe zu hinterlassen.
  Future<void> leaveGroup({required String groupId, required String uid}) async {
    final member = await _groupRepository.getMember(groupId, uid);
    if (member == null) {
      throw const GroupActionException('Du bist kein Mitglied dieser Gruppe.');
    }

    if (member.isAdmin) {
      final count = await _groupRepository.memberCount(groupId);
      if (count > 1) {
        throw const GroupActionException(
          'Bestimme zuerst ein anderes Mitglied als neuen Admin, bevor du die Gruppe verlässt.',
        );
      }
      await deleteGroup(groupId: groupId, callerUid: uid);
      return;
    }

    await _groupRepository.removeMember(groupId, uid);
  }

  Future<void> deleteGroup({required String groupId, required String callerUid}) async {
    await _requireAdmin(groupId, callerUid);
    await _storageService.deleteGroupImage(groupId);
    await _groupRepository.deleteGroup(groupId);
  }

  Future<void> _requireAdmin(String groupId, String uid) async {
    final member = await _groupRepository.getMember(groupId, uid);
    if (member == null || !member.isAdmin) {
      throw const GroupActionException('Nur der Admin der Gruppe darf diese Aktion ausführen.');
    }
  }
}
