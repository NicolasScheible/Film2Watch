import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../services/storage_service.dart';
import '../utils/profile_image_exceptions.dart';
import 'auth_provider.dart';
import 'storage_provider.dart';

const _supportedExtensions = ['.jpg', '.jpeg', '.png', '.heic', '.webp'];

/// Steuert Auswahl, Validierung und Upload/Löschung des Profilbilds.
/// Die eigentliche Kompression übernimmt bereits [ImagePicker] beim
/// Auswählen (`maxWidth`/`maxHeight`/`imageQuality`), sodass kein
/// zusätzliches Kompressions-Paket nötig ist.
class ProfileImageController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> pickAndUpload(ImageSource source) async {
    if (state.isLoading) return;

    final XFile? picked;
    try {
      picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
    } catch (_) {
      state = AsyncError(
        const ProfileImageException(
          'Zugriff nicht möglich. Bitte überprüfe die Berechtigungen in den Systemeinstellungen.',
        ),
        StackTrace.current,
      );
      return;
    }
    if (picked == null) return; // Nutzer hat abgebrochen.

    await uploadPickedFile(picked);
  }

  /// Validiert und lädt eine bereits ausgewählte Datei hoch. Getrennt von
  /// [pickAndUpload], damit die Upload-Logik ohne den nativen Bild-Picker
  /// (Platform Channel) testbar ist.
  @visibleForTesting
  Future<void> uploadPickedFile(XFile pickedFile) async {
    final uid = ref.read(authStateChangesProvider).value?.uid;
    if (uid == null || state.isLoading) return;

    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final file = File(pickedFile.path);
      if (!await file.exists()) {
        throw const ProfileImageException('Die ausgewählte Datei konnte nicht gefunden werden.');
      }
      if (!_hasSupportedExtension(pickedFile.name)) {
        throw const ProfileImageException(
          'Nicht unterstütztes Bildformat. Bitte JPG, PNG, HEIC oder WebP verwenden.',
        );
      }
      final sizeBytes = await file.length();
      if (sizeBytes > StorageService.maxUploadBytes) {
        throw const ProfileImageException(
          'Das Bild ist zu groß. Bitte wähle ein kleineres Bild.',
        );
      }

      final url = await ref
          .read(storageServiceProvider)
          .uploadProfileImage(uid: uid, file: file);
      await ref.read(userRepositoryProvider).updateProfilePicture(uid, url);
    });
  }

  Future<void> removeImage() async {
    final uid = ref.read(authStateChangesProvider).value?.uid;
    if (uid == null || state.isLoading) return;

    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(storageServiceProvider).deleteProfileImage(uid);
      await ref.read(userRepositoryProvider).clearProfilePicture(uid);
    });
  }

  bool _hasSupportedExtension(String fileName) {
    final lower = fileName.toLowerCase();
    return _supportedExtensions.any(lower.endsWith);
  }
}

final profileImageControllerProvider =
    AsyncNotifierProvider<ProfileImageController, void>(ProfileImageController.new);
