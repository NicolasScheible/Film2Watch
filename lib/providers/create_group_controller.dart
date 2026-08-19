import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/group_model.dart';
import '../utils/group_exceptions.dart';
import 'auth_provider.dart';
import 'group_provider.dart';
import 'storage_provider.dart';

const _supportedImageExtensions = ['.jpg', '.jpeg', '.png', '.heic', '.webp'];

/// Erstellt eine neue Gruppe, optional inkl. Gruppenbild. Das Bild kann erst
/// nach dem Anlegen der Gruppe hochgeladen werden, da der Storage-Pfad die
/// Gruppen-ID enthält.
class CreateGroupController extends AsyncNotifier<Group?> {
  @override
  Group? build() => null;

  Future<void> createGroup({required String name, File? photo, String? photoFileName}) async {
    final uid = ref.read(authStateChangesProvider).value?.uid;
    if (uid == null || state.isLoading) return;

    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final group = await ref
          .read(groupServiceProvider)
          .createGroup(name: name, creatorUid: uid);

      if (photo == null) return group;

      if (!await photo.exists()) {
        throw const GroupActionException('Das ausgewählte Bild konnte nicht gefunden werden.');
      }
      final lowerName = (photoFileName ?? photo.path).toLowerCase();
      if (!_supportedImageExtensions.any(lowerName.endsWith)) {
        throw const GroupActionException(
          'Nicht unterstütztes Bildformat. Bitte JPG, PNG, HEIC oder WebP verwenden.',
        );
      }

      final url = await ref
          .read(storageServiceProvider)
          .uploadGroupImage(groupId: group.id, file: photo);
      await ref.read(groupRepositoryProvider).updateGroupPhoto(group.id, url);
      return group;
    });
  }

  void reset() => state = const AsyncData(null);
}

final createGroupControllerProvider =
    AsyncNotifierProvider<CreateGroupController, Group?>(CreateGroupController.new);
