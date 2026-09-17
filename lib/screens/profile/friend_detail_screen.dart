import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../components/friends/user_avatar.dart';
import '../../components/movies/match_card.dart';
import '../../providers/friend_provider.dart';
import '../../providers/group_provider.dart';
import '../../providers/match_provider.dart';
import '../../theme/app_theme.dart';
import '../movies/movie_detail_screen.dart';

/// Freundes-Profil (§4 der Master-Spezifikation: "Im Profil sieht man seine
/// Freunde, gemeinsame Gruppen und vergangene Matches.") - mit dem
/// Produktverantwortlichen abgestimmt: Konzept_2.pdf ist für diesen Punkt
/// maßgeblich, auch wenn die detailliertere GUI-Spezifikation die beiden
/// Angaben in ihrer eigenen Freundesliste-Detailansicht nicht separat nennt.
///
/// Zeigt ausschließlich die beiden in §4 geforderten Datenpunkte - keine
/// weiteren Social-Features (keine Freundschaftsanfragen-Aktionen, kein
/// Chat-Einstieg, keine öffentlichen Profile).
class FriendDetailScreen extends ConsumerWidget {
  const FriendDetailScreen({super.key, required this.friendUid});

  final String friendUid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(publicProfileProvider(friendUid));

    return Scaffold(
      appBar: AppBar(title: Text(profileAsync.value?.name ?? 'Freund')),
      body: profileAsync.when(
        data: (profile) {
          if (profile == null) {
            return const Center(
              child: Text(
                'Profil konnte nicht geladen werden.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Center(
                child: UserAvatar(
                  name: profile.name,
                  profilePicture: profile.profilePicture,
                  radius: 44,
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(profile.name, style: Theme.of(context).textTheme.headlineSmall),
              ),
              const SizedBox(height: 32),
              Text('Gemeinsame Gruppen', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              _CommonGroupsSection(friendUid: friendUid),
              const SizedBox(height: 32),
              Text('Vergangene Matches', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              _PastMatchesSection(friendUid: friendUid),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.accent)),
        error: (error, _) => const Center(
          child: Text(
            'Profil konnte nicht geladen werden.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      ),
    );
  }
}

class _CommonGroupsSection extends ConsumerWidget {
  const _CommonGroupsSection({required this.friendUid});

  final String friendUid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupsAsync = ref.watch(commonGroupsWithFriendProvider(friendUid));

    return groupsAsync.when(
      data: (groups) {
        if (groups.isEmpty) {
          return const Text(
            'Keine gemeinsamen Gruppen.',
            style: TextStyle(color: AppColors.textSecondary),
          );
        }
        return Column(
          children: [
            for (final group in groups)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: UserAvatar(name: group.name, profilePicture: group.photoUrl, radius: 20),
                  title: Text(group.name),
                ),
              ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator(color: AppColors.accent)),
      error: (error, _) => const Text(
        'Gemeinsame Gruppen konnten nicht geladen werden.',
        style: TextStyle(color: AppColors.textSecondary),
      ),
    );
  }
}

class _PastMatchesSection extends ConsumerWidget {
  const _PastMatchesSection({required this.friendUid});

  final String friendUid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matchesAsync = ref.watch(pastMatchesWithFriendProvider(friendUid));

    return matchesAsync.when(
      data: (matches) {
        if (matches.isEmpty) {
          return const Text(
            'Noch keine gemeinsamen Matches.',
            style: TextStyle(color: AppColors.textSecondary),
          );
        }
        return SizedBox(
          height: 190,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: matches.length,
            separatorBuilder: (context, index) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final groupMatch = matches[index];
              return SizedBox(
                width: 120,
                child: MatchCard(
                  match: groupMatch.match,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => MovieDetailScreen(tmdbId: groupMatch.match.movieId),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator(color: AppColors.accent)),
      error: (error, _) => const Text(
        'Vergangene Matches konnten nicht geladen werden.',
        style: TextStyle(color: AppColors.textSecondary),
      ),
    );
  }
}
