import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/user_genre_preferences.dart';
import '../../providers/statistics_provider.dart';
import '../../providers/swipe_provider.dart';
import '../../providers/tmdb_provider.dart';
import '../../theme/app_theme.dart';

/// Persönliche Statistik-Ansicht (§15: "Detaillierte Statistiken",
/// Premium-Feature) - **mit dem Produktverantwortlichen abgestimmt**:
/// einfache Kennzahlen ausschließlich aus bereits vorhandenen Daten (siehe
/// `userStatisticsProvider`). Anders als das Super-Swipe-/Filter-Gating
/// (eine Aktion, die ehrlich fehlschlägt) ist dies eine reine Anzeige - ein
/// Free-User bekommt daher direkt einen Upsell-Hinweis statt eines leeren
/// oder falschen Datensatzes. Die zugrunde liegenden Daten (eigene Swipes/
/// Matches/Genre-Präferenzen) sind für JEDEN eingeloggten User ohnehin schon
/// heute lesbar (siehe `userStatisticsProvider`-Doc) - das Gating hier ist
/// ausschließlich ein Produkt-/UI-Entscheid, keine neue Sicherheitsgrenze.
class StatisticsScreen extends ConsumerWidget {
  const StatisticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Solange der Premium-Status noch lädt, wird nichts behauptet (kein
    // Upsell, keine Daten) - analog zum Super-Swipe-/Filter-Gating.
    final isPremiumAsync = ref.watch(isPremiumProvider);
    final isConfirmedFree = isPremiumAsync.hasValue && isPremiumAsync.value == false;

    return Scaffold(
      appBar: AppBar(title: const Text('Statistiken')),
      body: SafeArea(
        child: !isPremiumAsync.hasValue
            ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
            : isConfirmedFree
                ? const _PremiumUpsell()
                : const _StatisticsBody(),
      ),
    );
  }
}

class _StatisticsBody extends ConsumerWidget {
  const _StatisticsBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statisticsAsync = ref.watch(userStatisticsProvider);
    final genresAsync = ref.watch(movieGenresProvider);

    return statisticsAsync.when(
      data: (statistics) {
        if (statistics.swipeCount == 0 && statistics.matchCount == 0) {
          return const _EmptyStatisticsState();
        }
        final genreNames = genresAsync.value ?? const {};
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _StatTile(
              icon: Icons.swipe,
              label: 'Swipes',
              value: statistics.swipeCount,
            ),
            _StatTile(
              icon: Icons.favorite,
              label: 'Likes',
              value: statistics.likeCount,
            ),
            _StatTile(
              icon: Icons.close_rounded,
              label: 'Dislikes',
              value: statistics.dislikeCount,
            ),
            _StatTile(
              icon: Icons.bookmark_add_outlined,
              label: 'Watchlist',
              value: statistics.watchlistCount,
            ),
            _StatTile(
              icon: Icons.people_alt_outlined,
              label: 'Matches',
              value: statistics.matchCount,
            ),
            const SizedBox(height: 12),
            _TopGenresSection(
              genrePreferences: statistics.genrePreferences,
              genreNames: genreNames,
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator(color: AppColors.accent)),
      error: (error, _) => const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Statistiken konnten nicht geladen werden.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.accentSecondary),
          const SizedBox(width: 16),
          Expanded(
            child: Text(label, style: const TextStyle(color: AppColors.textPrimary, fontSize: 15)),
          ),
          Text(
            '$value',
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Bis zu drei Lieblingsgenres nach Genre-Affinität sortiert (§7:
/// `top_genres`, bereits serverseitig vorberechnet) - Genre-Namen kommen von
/// TMDB (`movieGenresProvider`, dieselbe Quelle wie im Filter, §10), keine
/// eigene Genre-Liste. Solange die Namen noch laden, wird die numerische
/// TMDB-Genre-ID als Fallback angezeigt statt nichts anzuzeigen.
class _TopGenresSection extends StatelessWidget {
  const _TopGenresSection({required this.genrePreferences, required this.genreNames});

  final UserGenrePreferences genrePreferences;
  final Map<int, String> genreNames;

  @override
  Widget build(BuildContext context) {
    final sortedTopGenres = genrePreferences.topGenres.toList()
      ..sort((a, b) {
        final affinityA = genrePreferences.genreAffinity[a] ?? 0;
        final affinityB = genrePreferences.genreAffinity[b] ?? 0;
        return affinityB.compareTo(affinityA);
      });

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Lieblingsgenres',
            style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 15),
          ),
          const SizedBox(height: 12),
          if (sortedTopGenres.isEmpty)
            const Text(
              'Noch keine Genre-Vorliebe erkannt - like ein paar Filme.',
              style: TextStyle(color: AppColors.textSecondary),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final genreId in sortedTopGenres)
                  Chip(
                    label: Text(genreNames[genreId] ?? 'Genre $genreId'),
                    backgroundColor: AppColors.surface,
                    labelStyle: const TextStyle(color: AppColors.textPrimary),
                    side: BorderSide.none,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _PremiumUpsell extends StatelessWidget {
  const _PremiumUpsell();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 56, color: AppColors.textSecondary),
            SizedBox(height: 16),
            Text(
              'Statistiken sind ein Premium-Feature.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 8),
            Text(
              'Werde Premium-Mitglied, um deine Swipe- und Match-Statistiken zu sehen.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyStatisticsState extends StatelessWidget {
  const _EmptyStatisticsState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bar_chart, size: 56, color: AppColors.textSecondary),
            SizedBox(height: 16),
            Text(
              'Noch keine Daten - swipe ein paar Filme, um deine Statistiken zu sehen.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}
