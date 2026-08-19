import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../components/auth/auth_text_field.dart';
import '../../components/auth/primary_button.dart';
import '../../components/auth/social_sign_in_button.dart';
import '../../providers/auth_form_controller.dart';
import '../../theme/app_theme.dart';
import '../../utils/auth_error_translator.dart';
import '../../utils/auth_validators.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, required this.onSwitchToRegister});

  final VoidCallback onSwitchToRegister;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    ref.read(authFormControllerProvider.notifier).signInWithEmail(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
  }

  void _forgotPassword() {
    final email = _emailController.text.trim();
    final error = AuthValidators.email(email);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Bitte gib zuerst deine E-Mail-Adresse ein.')),
      );
      return;
    }
    ref.read(authFormControllerProvider.notifier).sendPasswordResetEmail(email);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Falls ein Account existiert, wurde eine E-Mail zum Zurücksetzen gesendet.')),
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
          Text('Willkommen zurück', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text(
            'Melde dich an, um mit deinen Freunden Filme zu entdecken.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 32),
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
            textInputAction: TextInputAction.done,
            enabled: !isLoading,
            autofillHints: const [AutofillHints.password],
            validator: AuthValidators.password,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: isLoading ? null : _forgotPassword,
              child: const Text('Passwort vergessen?'),
            ),
          ),
          const SizedBox(height: 8),
          PrimaryButton(
            label: 'Einloggen',
            isLoading: isLoading,
            onPressed: _submit,
          ),
          const SizedBox(height: 24),
          const _OrDivider(),
          const SizedBox(height: 24),
          SocialSignInButton(
            label: 'Mit Google anmelden',
            icon: Icons.g_mobiledata_rounded,
            isLoading: isLoading,
            onPressed: () =>
                ref.read(authFormControllerProvider.notifier).signInWithGoogle(),
          ),
          const SizedBox(height: 12),
          SocialSignInButton(
            label: 'Mit Apple anmelden',
            icon: Icons.apple,
            isLoading: isLoading,
            onPressed: () =>
                ref.read(authFormControllerProvider.notifier).signInWithApple(),
          ),
          const SizedBox(height: 32),
          Center(
            child: TextButton(
              onPressed: isLoading ? null : widget.onSwitchToRegister,
              child: const Text('Noch keinen Account? Jetzt registrieren'),
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
