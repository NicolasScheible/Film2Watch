import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'login_screen.dart';
import 'register_screen.dart';

/// Login-/Registrierungsbereich von Film2Watch. Wird angezeigt, solange
/// kein Firebase-User authentifiziert ist.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _showLogin = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight - 64),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const _Film2WatchLogo(),
                    const SizedBox(height: 40),
                    if (_showLogin)
                      LoginScreen(onSwitchToRegister: () => setState(() => _showLogin = false))
                    else
                      RegisterScreen(onSwitchToLogin: () => setState(() => _showLogin = true)),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Film2WatchLogo extends StatelessWidget {
  const _Film2WatchLogo();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: AppColors.accent,
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Icon(Icons.movie_filter_rounded, color: Colors.white, size: 34),
        ),
        const SizedBox(height: 16),
        const Text(
          'Film2Watch',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Gemeinsam entscheiden, was ihr schaut.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}
