import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../components/movies/match_card.dart';
import '../../providers/match_provider.dart';
import '../../theme/app_theme.dart';
import '../movies/movie_detail_screen.dart';

/// Echte, gruppenübergreifende Match-Übersicht: zeigt alle Matches aus allen
/// Gruppen des Nutzers in Echtzeit (`allMyMatchesProvider`), neueste zuerst.
/// Jede Karte zeigt zusätzlich die Gruppe, in der der Match entstanden ist.
/// Antippen öffnet die echten TMDB-Filmdetails - dieselbe Anzeige wie beim
/// Match in der einzelnen Gruppe, keine zweite, redundante Detailseite.
class MatchesScreen extends ConsumerWidget {
  const MatchesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matchesAsync = ref.watch(allMyMatchesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Matches')),
      body: matchesAsync.when(
        data: (matches) {
          if (matches.isEmpty) return const _EmptyMatchesState();
          return GridView.builder(
            padding: const EdgeInsets.all(20),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 160,
              mainAxisSpacing: 20,
              crossAxisSpacing: 16,
              childAspectRatio: 0.58,
            ),
            itemCount: matches.length,
            itemBuilder: (context, index) {
              final groupMatch = matches[index];
              return _GroupMatchTile(groupMatch: groupMatch);
            },
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.accent),
        ),
        error: (error, _) => const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Matches konnten nicht geladen werden.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ),
      ),
    );
  }
}

class _GroupMatchTile extends StatelessWidget {
  const _GroupMatchTile({required this.groupMatch});

  final GroupMatch groupMatch;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6, left: 2),
          child: Text(
            groupMatch.group.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: MatchCard(
            match: groupMatch.match,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    MovieDetailScreen(tmdbId: groupMatch.match.movieId),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyMatchesState extends StatelessWidget {
  const _EmptyMatchesState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.favorite_border,
              size: 56,
              color: AppColors.textSecondary,
            ),
            SizedBox(height: 16),
            Text(
              'Noch keine gemeinsamen Filme.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}
