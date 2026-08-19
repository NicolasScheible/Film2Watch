import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../components/auth/auth_text_field.dart';
import '../../components/auth/primary_button.dart';
import '../../components/friends/user_avatar.dart';
import '../../providers/group_action_controller.dart';
import '../../providers/group_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/group_error_translator.dart';
import '../../utils/group_validators.dart';

/// Gruppe bearbeiten: Name sowie Gruppenbild ändern/entfernen. Nur für
/// Admins erreichbar.
class EditGroupScreen extends ConsumerStatefulWidget {
  const EditGroupScreen({super.key, required this.groupId});

  final String groupId;

  @override
  ConsumerState<EditGroupScreen> createState() => _EditGroupScreenState();
}

class _EditGroupScreenState extends ConsumerState<EditGroupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  bool _nameInitialized = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (picked != null) {
      ref.read(groupActionControllerProvider.notifier).uploadGroupImage(
            widget.groupId,
            File(picked.path),
          );
    }
  }

  Future<void> _confirmRemoveImage() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Gruppenbild entfernen'),
        content: const Text('Möchtest du das Gruppenbild wirklich entfernen?'),
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
      ref.read(groupActionControllerProvider.notifier).removeGroupImage(widget.groupId);
    }
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    ref
        .read(groupActionControllerProvider.notifier)
        .renameGroup(widget.groupId, _nameController.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final group = ref.watch(groupProvider(widget.groupId)).value;
    final actionState = ref.watch(groupActionControllerProvider);
    final isLoading = actionState.isLoading;

    if (!_nameInitialized && group != null) {
      _nameController.text = group.name;
      _nameInitialized = true;
    }

    ref.listen(groupActionControllerProvider, (previous, next) {
      next.whenOrNull(
        error: (error, _) => ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(translateGroupError(error)))),
      );
    });

    if (group == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppColors.accent)),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Gruppe bearbeiten')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: UserAvatar(
                  name: group.name,
                  profilePicture: group.photoUrl,
                  radius: 44,
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: isLoading ? null : _pickImage,
                  child: const Text('Gruppenbild ändern'),
                ),
              ),
              if (group.photoUrl != null)
                Center(
                  child: TextButton(
                    onPressed: isLoading ? null : _confirmRemoveImage,
                    child: const Text(
                      'Gruppenbild entfernen',
                      style: TextStyle(color: Colors.redAccent),
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              AuthTextField(
                label: 'Gruppenname',
                controller: _nameController,
                enabled: !isLoading,
                validator: GroupValidators.name,
              ),
              const SizedBox(height: 24),
              PrimaryButton(label: 'Speichern', isLoading: isLoading, onPressed: _save),
            ],
          ),
        ),
      ),
    );
  }
}
