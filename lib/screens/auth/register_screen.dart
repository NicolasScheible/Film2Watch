import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../components/auth/auth_text_field.dart';
import '../../components/auth/primary_button.dart';
import '../../components/auth/social_sign_in_button.dart';
import '../../providers/auth_form_controller.dart';
import '../../theme/app_theme.dart';
import '../../utils/auth_error_translator.dart';
import '../../utils/auth_validators.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key, required this.onSwitchToLogin});

  final VoidCallback onSwitchToLogin;

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    ref.read(authFormControllerProvider.notifier).registerWithEmail(
          name: _nameController.text.trim(),
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final formState = ref.watch(authFormControllerProvider);
    final isLoading = formState.isLoading;

    ref.listen(authFormControllerProvider, (previous, next) {
      next.whenOrNull(
        error: (error, _) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(translateAuthError(error))),
          );
        },
      );
    });

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Account erstellen', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text(
            'Erstelle deinen Film2Watch-Account und lade deine Freunde ein.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 32),
          AuthTextField(
            label: 'Name',
            controller: _nameController,
            textInputAction: TextInputAction.next,
            enabled: !isLoading,
            autofillHints: const [AutofillHints.name],
            validator: AuthValidators.name,
          ),
          const SizedBox(height: 16),
          AuthTextField(
            label: 'E-Mail',
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            enabled: !isLoading,
            autofillHints: const [AutofillHints.email],
            validator: AuthValidators.email,
          ),
          const SizedBox(height: 16),
          AuthTextField(
            label: 'Passwort',
            controller: _passwordController,
            obscureText: true,
            textInputAction: TextInputAction.next,
            enabled: !isLoading,
            autofillHints: const [AutofillHints.newPassword],
            validator: AuthValidators.password,
          ),
          const SizedBox(height: 16),
          AuthTextField(
            label: 'Passwort bestätigen',
            controller: _confirmPasswordController,
            obscureText: true,
            textInputAction: TextInputAction.done,
            enabled: !isLoading,
            validator: (value) => AuthValidators.passwordConfirmation(
              _passwordController.text,
              value ?? '',
            ),
          ),
          const SizedBox(height: 24),
          PrimaryButton(
            label: 'Account erstellen',
            isLoading: isLoading,
            onPressed: _submit,
          ),
          const SizedBox(height: 24),
          const _OrDivider(),
          const SizedBox(height: 24),
          SocialSignInButton(
            label: 'Mit Google registrieren',
            icon: Icons.g_mobiledata_rounded,
            isLoading: isLoading,
            onPressed: () =>
                ref.read(authFormControllerProvider.notifier).signInWithGoogle(),
          ),
          const SizedBox(height: 12),
          SocialSignInButton(
            label: 'Mit Apple registrieren',
            icon: Icons.apple,
            isLoading: isLoading,
            onPressed: () =>
                ref.read(authFormControllerProvider.notifier).signInWithApple(),
          ),
          const SizedBox(height: 32),
          Center(
            child: TextButton(
              onPressed: isLoading ? null : widget.onSwitchToLogin,
              child: const Text('Du hast schon einen Account? Jetzt einloggen'),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(child: Divider(color: AppColors.surfaceVariant)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text('oder', style: TextStyle(color: AppColors.textSecondary)),
        ),
        Expanded(child: Divider(color: AppColors.surfaceVariant)),
      ],
    );
  }
}
