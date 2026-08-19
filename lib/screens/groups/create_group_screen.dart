import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../components/auth/auth_text_field.dart';
import '../../components/auth/primary_button.dart';
import '../../components/friends/user_avatar.dart';
import '../../providers/create_group_controller.dart';
import '../../theme/app_theme.dart';
import '../../utils/group_error_translator.dart';
import '../../utils/group_validators.dart';
import 'group_detail_screen.dart';

/// Neue Gruppe erstellen: Name (Pflicht) und optional ein Gruppenbild.
class CreateGroupScreen extends ConsumerStatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  ConsumerState<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends ConsumerState<CreateGroupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  XFile? _selectedPhoto;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (picked != null) setState(() => _selectedPhoto = picked);
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    ref.read(createGroupControllerProvider.notifier).createGroup(
          name: _nameController.text.trim(),
          photo: _selectedPhoto != null ? File(_selectedPhoto!.path) : null,
          photoFileName: _selectedPhoto?.name,
        );
  }

  @override
  Widget build(BuildContext context) {
    final createState = ref.watch(createGroupControllerProvider);
    final isLoading = createState.isLoading;

    ref.listen(createGroupControllerProvider, (previous, next) {
      next.whenOrNull(
        error: (error, _) => ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(translateGroupError(error)))),
        data: (group) {
          if (group != null && (previous?.isLoading ?? false)) {
            ref.read(createGroupControllerProvider.notifier).reset();
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => GroupDetailScreen(groupId: group.id)),
            );
          }
        },
      );
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Gruppe erstellen')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: GestureDetector(
                  onTap: isLoading ? null : _pickPhoto,
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      _selectedPhoto != null
                          ? CircleAvatar(
                              radius: 44,
                              backgroundColor: AppColors.surfaceVariant,
                              backgroundImage: FileImage(File(_selectedPhoto!.path)),
                            )
                          : const UserAvatar(name: '', radius: 44),
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: AppColors.accent,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.edit, size: 16, color: Colors.white),
                      ),
                    ],
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
              PrimaryButton(
                label: 'Gruppe erstellen',
                isLoading: isLoading,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
