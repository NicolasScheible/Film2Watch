import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../components/auth/primary_button.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';

class _OnboardingSlide {
  const _OnboardingSlide({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;
}

const _slides = [
  _OnboardingSlide(
    icon: Icons.swipe_outlined,
    title: 'Rechts oder links wischen',
    description:
        'Rechts = Gefällt mir, links = Nicht mein Fall. So bewertest du Filme in deinen Gruppen.',
  ),
  _OnboardingSlide(
    icon: Icons.swipe_vertical_outlined,
    title: 'Vielleicht später?',
    description:
        'Runter überspringt einen Film nur für dich, hoch setzt ihn auf deine persönliche '
        'Watchlist – beides beeinflusst niemanden sonst in der Gruppe.',
  ),
  _OnboardingSlide(
    icon: Icons.person_add_alt_1_outlined,
    title: 'Freunde per Code hinzufügen',
    description:
        'Jeder Nutzer hat einen eigenen Freundescode (z. B. FILM-4821). Gib den Code eines '
        'Freundes in deinem Profil ein, um euch zu verbinden.',
  ),
];

/// Wird genau einmal pro Nutzer gezeigt, direkt nachdem das Profil
/// vervollständigt wurde (siehe `AppGate`) - erklärt die Swipe-Richtungen und
/// das Hinzufügen von Freunden per Code. Persistiert den Abschluss
/// serverseitig auf `users/{uid}.onboarding_completed`, damit `AppGate`
/// reaktiv zu `AppShell` weiterschaltet und das Tutorial bei einem Login auf
/// einem anderen Gerät nicht erneut erscheint.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;
  bool _isSaving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _complete() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      final uid = ref.read(authStateChangesProvider).value?.uid;
      if (uid == null) return;
      await ref.read(userRepositoryProvider).completeOnboarding(uid);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Konnte nicht gespeichert werden. Bitte versuche es erneut.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _next() {
    if (_page < _slides.length - 1) {
      _controller.nextPage(duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
    } else {
      _complete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLastPage = _page == _slides.length - 1;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: TextButton(
                onPressed: _isSaving ? null : _complete,
                child: const Text(
                  'Überspringen',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _slides.length,
                onPageChanged: (page) => setState(() => _page = page),
                itemBuilder: (context, index) => _SlideContent(slide: _slides[index]),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _slides.length; i++)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i == _page ? AppColors.accent : AppColors.surfaceVariant,
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: PrimaryButton(
                label: isLastPage ? 'Los geht\'s' : 'Weiter',
                isLoading: _isSaving,
                onPressed: _next,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SlideContent extends StatelessWidget {
  const _SlideContent({required this.slide});

  final _OnboardingSlide slide;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(slide.icon, size: 96, color: AppColors.accent),
          const SizedBox(height: 32),
          Text(
            slide.title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          Text(
            slide.description,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary, height: 1.4),
          ),
        ],
      ),
    );
  }
}
