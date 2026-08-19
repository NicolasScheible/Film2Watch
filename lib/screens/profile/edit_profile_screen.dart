import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../components/auth/auth_text_field.dart';
import '../../components/auth/primary_button.dart';
import '../../components/friends/user_avatar.dart';
import '../../providers/auth_provider.dart';
import '../../providers/profile_edit_controller.dart';
import '../../providers/profile_image_controller.dart';
import '../../theme/app_theme.dart';
import '../../utils/auth_error_translator.dart';
import '../../utils/auth_validators.dart';
import '../../utils/profile_image_error_translator.dart';

/// Profil bearbeiten: Name sowie Profilbild ändern/entfernen.
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    final currentUser = ref.read(currentUserDocProvider).value;
    _nameController = TextEditingController(text: currentUser?.name ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    ref.read(profileEditControllerProvider.notifier).updateName(_nameController.text.trim());
  }

  Future<void> _showImageSourcePicker() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined, color: AppColors.textPrimary),
              title: const Text('Kamera'),
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: AppColors.textPrimary),
              title: const Text('Galerie'),
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.close, color: AppColors.textSecondary),
              title: const Text('Abbrechen'),
              onTap: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    ref.read(profileImageControllerProvider.notifier).pickAndUpload(source);
  }

  Future<void> _confirmRemoveImage() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Profilbild entfernen'),
        content: const Text('Möchtest du dein Profilbild wirklich entfernen?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Abbrechen')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Entfernen', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      ref.read(profileImageControllerProvider.notifier).removeImage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserDocProvider).value;
    final editState = ref.watch(profileEditControllerProvider);
    final imageState = ref.watch(profileImageControllerProvider);
    final isImageLoading = imageState.isLoading;

    ref.listen(profileEditControllerProvider, (previous, next) {
      next.whenOrNull(
        error: (error, _) => ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(translateAuthError(error)))),
        data: (_) {
          if (previous?.isLoading ?? false) {
            Navigator.of(context).pop();
          }
        },
      );
    });

    ref.listen(profileImageControllerProvider, (previous, next) {
      next.whenOrNull(
        error: (error, _) => ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(translateProfileImageError(error)))),
      );
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Profil bearbeiten')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    UserAvatar(
                      name: currentUser?.name ?? '',
                      profilePicture: currentUser?.profilePicture,
                      radius: 44,
                    ),
                    if (isImageLoading)
                      const CircleAvatar(
                        radius: 44,
                        backgroundColor: Colors.black45,
                        child: CircularProgressIndicator(color: AppColors.accent),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: isImageLoading ? null : _showImageSourcePicker,
                  child: const Text('Profilbild ändern'),
                ),
              ),
              if (currentUser?.profilePicture != null)
                Center(
                  child: TextButton(
                    onPressed: isImageLoading ? null : _confirmRemoveImage,
                    child: const Text(
                      'Profilbild entfernen',
                      style: TextStyle(color: Colors.redAccent),
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              AuthTextField(
                label: 'Name',
                controller: _nameController,
                enabled: !editState.isLoading,
                autofillHints: const [AutofillHints.name],
                validator: AuthValidators.name,
              ),
              const SizedBox(height: 24),
              PrimaryButton(
                label: 'Speichern',
                isLoading: editState.isLoading,
                onPressed: _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
