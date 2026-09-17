import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/group_invitation.dart';
import '../models/group_member.dart';
import '../models/group_model.dart';

/// Kapselt den Firestore-Zugriff auf `groups`, `groups/{id}/members` und
/// `group_invitations`. Spiegelt exakt das Sicherheitsmodell aus
/// `firestore.rules` wider.
class GroupRepository {
  GroupRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _groups => _firestore.collection('groups');

  CollectionReference<Map<String, dynamic>> _members(String groupId) =>
      _groups.doc(groupId).collection('members');

  CollectionReference<Map<String, dynamic>> get _invitations =>
      _firestore.collection('group_invitations');

  String _invitationId(String groupId, String inviteeUid) => '${groupId}_$inviteeUid';

  // ---- Gruppen ----

  /// Erstellt die Gruppe und anschließend die Admin-Mitgliedschaft des
  /// Erstellers als zwei sequenzielle Schreibvorgänge (kein Batch): die
  /// Firestore Rules für die Erst-Mitgliedschaft prüfen `created_by` auf dem
  /// bereits committeten Gruppendokument, was innerhalb eines Batches nicht
  /// zuverlässig sichtbar wäre. Schlägt die zweite Schreibaktion fehl, wird
  /// die verwaiste Gruppe wieder gelöscht, statt eine Gruppe ohne Mitglieder
  /// zurückzulassen.
  Future<Group> createGroup({required String name, required String creatorUid}) async {
    final now = DateTime.now();
    final groupRef = _groups.doc();
    final group = Group(
      id: groupRef.id,
      name: name,
      createdBy: creatorUid,
      createdAt: now,
      updatedAt: now,
    );

    await groupRef.set(group.toFirestore());
    try {
      final member = GroupMember(uid: creatorUid, role: GroupRole.admin, joinedAt: now);
      await _members(group.id).doc(creatorUid).set(member.toFirestore());
    } catch (_) {
      await groupRef.delete();
      rethrow;
    }
    return group;
  }

  Future<Group?> getGroup(String groupId) async {
    final snapshot = await _groups.doc(groupId).get();
    return snapshot.exists ? Group.fromFirestore(snapshot) : null;
  }

  Stream<Group?> watchGroup(String groupId) {
    return _groups.doc(groupId).snapshots().map((s) => s.exists ? Group.fromFirestore(s) : null);
  }

  /// Alle Gruppen, in denen [uid] Mitglied ist (Collection-Group-Query über
  /// `members`, benötigt den in `firestore.indexes.json` deklarierten Index).
  Stream<List<Group>> watchMyGroups(String uid) {
    return _firestore
        .collectionGroup('members')
        .where('uid', isEqualTo: uid)
        .snapshots()
        .asyncMap((snapshot) async {
      final groupIds = snapshot.docs.map((doc) => doc.reference.parent.parent!.id).toSet();
      final groupDocs = await Future.wait(groupIds.map((id) => _groups.doc(id).get()));
      return groupDocs.where((doc) => doc.exists).map(Group.fromFirestore).toList();
    });
  }

  /// Gruppen, in denen sowohl [currentUid] als auch [friendUid] Mitglied
  /// sind (§4: "gemeinsame Gruppen" im Freundes-Profil) - die Schnittmenge
  /// zweier Mitgliedschafts-Queries, exakt wie bei [watchMyGroups], hier
  /// zusätzlich client-seitig geschnitten. Firestore Rules (`isGroupMember`
  /// prüft immer die Mitgliedschaft des *aufrufenden* Users, nie die des
  /// abgefragten `uid`-Feldwerts) lassen eine reine
  /// `members.where('uid', isEqualTo: friendUid)`-Query ohnehin nur
  /// Ergebnisse aus Gruppen zurückgeben, in denen [currentUid] selbst
  /// Mitglied ist - die explizite Schnittmenge hier ist eine zusätzliche,
  /// unabhängig von den Rules korrekte Absicherung (u. a. damit dieses
  /// Verhalten auch mit `fake_cloud_firestore`, das keine Rules erzwingt,
  /// sinnvoll testbar ist).
  Stream<List<Group>> watchCommonGroups({
    required String currentUid,
    required String friendUid,
  }) {
    return _firestore
        .collectionGroup('members')
        .where('uid', isEqualTo: friendUid)
        .snapshots()
        .asyncMap((friendSnapshot) async {
      final friendGroupIds =
          friendSnapshot.docs.map((doc) => doc.reference.parent.parent!.id).toSet();
      if (friendGroupIds.isEmpty) return const <Group>[];

      final mySnapshot = await _firestore
          .collectionGroup('members')
          .where('uid', isEqualTo: currentUid)
          .get();
      final myGroupIds = mySnapshot.docs.map((doc) => doc.reference.parent.parent!.id).toSet();

      final commonGroupIds = friendGroupIds.intersection(myGroupIds);
      if (commonGroupIds.isEmpty) return const <Group>[];

      final groupDocs = await Future.wait(commonGroupIds.map((id) => _groups.doc(id).get()));
      return groupDocs.where((doc) => doc.exists).map(Group.fromFirestore).toList();
    });
  }

  /// Anzahl der Gruppen, in denen [uid] aktuell Mitglied ist (§15:
  /// Free-Gruppen-Limit) - live per Aggregations-Query auf dieselbe
  /// Collection-Group wie [watchMyGroups], daher ohne Verzögerung exakt (im
  /// Gegensatz zum serverseitig für die Firestore Rules gepflegten,
  /// asynchronen Zähler `group_membership_counts/{uid}`). Nur für eine
  /// clientseitige Vorab-Prüfung mit sofortigem, verständlichem
  /// Fehlertext gedacht - die eigentliche, sicherheitsrelevante Durchsetzung
  /// bleibt unabhängig davon immer serverseitig (Firestore Rules
  /// `groupMembershipCount()`).
  Future<int> myGroupCount(String uid) async {
    final result = await _firestore
        .collectionGroup('members')
        .where('uid', isEqualTo: uid)
        .count()
        .get();
    return result.count ?? 0;
  }

  Future<void> updateGroupName(String groupId, String name) {
    return _groups.doc(groupId).update({
      'name': name,
      'updated_at': Timestamp.fromDate(DateTime.now()),
    });
  }

  Future<void> updateGroupPhoto(String groupId, String? photoUrl) {
    return _groups.doc(groupId).update({
      'photo_url': photoUrl,
      'updated_at': Timestamp.fromDate(DateTime.now()),
    });
  }

  /// Löscht die Gruppe inkl. aller Mitgliedschaften und offenen Einladungen
  /// atomar in einem Batch. Firestore-Batches sind auf 500 Operationen
  /// begrenzt; bei außergewöhnlich großen Gruppen (>499 Mitglieder+Einladungen)
  /// schlägt der Batch kontrolliert fehl, statt unvollständig zu löschen.
  Future<void> deleteGroup(String groupId) async {
    final memberDocs = await _members(groupId).get();
    final invitationDocs = await _invitations.where('groupId', isEqualTo: groupId).get();

    final batch = _firestore.batch();
    for (final doc in memberDocs.docs) {
      batch.delete(doc.reference);
    }
    for (final doc in invitationDocs.docs) {
      batch.delete(doc.reference);
    }
    batch.delete(_groups.doc(groupId));
    await batch.commit();
  }

  // ---- Mitglieder ----

  Future<GroupMember?> getMember(String groupId, String uid) async {
    final snapshot = await _members(groupId).doc(uid).get();
    return snapshot.exists ? GroupMember.fromFirestore(snapshot) : null;
  }

  Stream<List<GroupMember>> watchMembers(String groupId) {
    return _members(groupId)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(GroupMember.fromFirestore).toList());
  }

  Future<int> memberCount(String groupId) async {
    final result = await _members(groupId).count().get();
    return result.count ?? 0;
  }

  Future<void> removeMember(String groupId, String uid) {
    return _members(groupId).doc(uid).delete();
  }

  Future<void> updateMemberRole(String groupId, String uid, GroupRole role) {
    return _members(groupId).doc(uid).update({'role': role.name});
  }

  /// Überträgt die Admin-Rolle atomar: [newAdminUid] wird Admin, der
  /// bisherige Admin wird zum normalen Mitglied.
  Future<void> transferAdmin({
    required String groupId,
    required String currentAdminUid,
    required String newAdminUid,
  }) {
    final batch = _firestore.batch();
    batch.update(_members(groupId).doc(newAdminUid), {'role': GroupRole.admin.name});
    batch.update(_members(groupId).doc(currentAdminUid), {'role': GroupRole.member.name});
    return batch.commit();
  }

  // ---- Einladungen ----

  Future<bool> invitationExists(String groupId, String inviteeUid) async {
    final snapshot = await _invitations.doc(_invitationId(groupId, inviteeUid)).get();
    return snapshot.exists;
  }

  Future<void> createInvitation({
    required String groupId,
    required String inviterUid,
    required String inviteeUid,
  }) {
    final invitation = GroupInvitation(
      id: _invitationId(groupId, inviteeUid),
      groupId: groupId,
      inviterUid: inviterUid,
      inviteeUid: inviteeUid,
      createdAt: DateTime.now(),
    );
    return _invitations.doc(invitation.id).set(invitation.toFirestore());
  }

  Stream<List<GroupInvitation>> watchIncomingInvitations(String uid) {
    return _invitations
        .where('inviteeUid', isEqualTo: uid)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(GroupInvitation.fromFirestore).toList());
  }

  /// Nimmt eine Einladung an: legt atomar die Mitgliedschaft an und löscht
  /// die Einladung in einem Batch.
  Future<void> acceptInvitation({required String groupId, required String inviteeUid}) {
    final batch = _firestore.batch();
    final member = GroupMember(uid: inviteeUid, role: GroupRole.member, joinedAt: DateTime.now());
    batch.set(_members(groupId).doc(inviteeUid), member.toFirestore());
    batch.delete(_invitations.doc(_invitationId(groupId, inviteeUid)));
    return batch.commit();
  }

  Future<void> declineInvitation({required String groupId, required String inviteeUid}) {
    return _invitations.doc(_invitationId(groupId, inviteeUid)).delete();
  }
}
