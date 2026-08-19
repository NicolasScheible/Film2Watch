import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../components/auth/auth_text_field.dart';
import '../../components/auth/primary_button.dart';
import '../../components/friends/user_avatar.dart';
import '../../providers/auth_provider.dart';
import '../../providers/profile_edit_controller.dart';
import '../../theme/app_theme.dart';
import '../../utils/auth_error_translator.dart';
import '../../utils/auth_validators.dart';

/// Profil bearbeiten. Nur der Name ist aktuell änderbar - das Ändern des
/// Profilbilds erfordert Firebase Storage, das für dieses Projekt noch
/// nicht bestätigt eingerichtet ist (siehe README).
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

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserDocProvider).value;
    final editState = ref.watch(profileEditControllerProvider);

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
                child: UserAvatar(
                  name: currentUser?.name ?? '',
                  profilePicture: currentUser?.profilePicture,
                  radius: 44,
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
              const SizedBox(height: 16),
              const Text(
                'Profilbild ändern ist bald verfügbar.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
