import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../components/auth/auth_text_field.dart';
import '../../components/auth/primary_button.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/auth_validators.dart';

/// Wird angezeigt, wenn nach einem Google-/Apple-Login noch kein Name für
/// das User-Dokument vorliegt (z. B. weil Apple ihn nicht übermittelt hat).
/// Es wird kein Name erraten oder zufällig generiert – der Nutzer trägt ihn
/// selbst ein.
class CompleteProfileScreen extends ConsumerStatefulWidget {
  const CompleteProfileScreen({super.key});

  @override
  ConsumerState<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends ConsumerState<CompleteProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  bool _isSaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _isSaving) return;
    setState(() => _isSaving = true);

    final user = ref.read(authStateChangesProvider).value;
    if (user == null) return;

    try {
      await ref
          .read(userRepositoryProvider)
          .updateName(user.uid, _nameController.text.trim());
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Name konnte nicht gespeichert werden. Bitte versuche es erneut.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Fast geschafft!', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                const Text(
                  'Wie sollen dich deine Freunde bei Film2Watch sehen?',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 24),
                AuthTextField(
                  label: 'Name',
                  controller: _nameController,
                  enabled: !_isSaving,
                  autofillHints: const [AutofillHints.name],
                  validator: AuthValidators.name,
                ),
                const SizedBox(height: 24),
                PrimaryButton(
                  label: 'Weiter',
                  isLoading: _isSaving,
                  onPressed: _save,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
