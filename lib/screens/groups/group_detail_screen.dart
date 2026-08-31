import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../components/friends/user_avatar.dart';
import '../../components/movies/match_card.dart';
import '../../components/movies/watchlist_card.dart';
import '../../models/group_member.dart';
import '../../providers/auth_provider.dart';
import '../../providers/friend_provider.dart';
import '../../providers/group_action_controller.dart';
import '../../providers/group_provider.dart';
import '../../providers/match_provider.dart';
import '../../providers/swipe_provider.dart';
import '../../providers/watchlist_remove_controller.dart';
import '../../theme/app_theme.dart';
import '../../utils/group_error_translator.dart';
import '../movies/movie_detail_screen.dart';
import 'edit_group_screen.dart';
import 'group_chat_screen.dart';
import 'group_swipe_screen.dart';
import 'invite_friend_screen.dart';

/// Detailseite einer Gruppe: Bild, Name, Mitglieder, rollenabhängige
/// Aktionen, der Einstieg in die Gruppen-Swipe-Session, die echte
/// Match-Liste, der gruppenweite Watchlist-Abgleich sowie der echte
/// Gruppenchat.
class GroupDetailScreen extends ConsumerWidget {
  const GroupDetailScreen({super.key, required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final group = ref.watch(groupProvider(groupId));
    final members = ref.watch(groupMembersProvider(groupId));
    final myMembership = ref.watch(myMembershipProvider(groupId));
    final isAdmin = myMembership?.isAdmin ?? false;

    ref.listen(groupActionControllerProvider, (previous, next) {
      next.whenOrNull(
        error: (error, _) => ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(translateGroupError(error)))),
      );
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(group.value?.name ?? 'Gruppe'),
        actions: [
          if (isAdmin)
            IconButton(
              tooltip: 'Gruppe bearbeiten',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => EditGroupScreen(groupId: groupId)),
              ),
            ),
        ],
      ),
      body: group.when(
        data: (group) {
          if (group == null) {
            // Gruppe existiert nicht mehr (z. B. gerade gelöscht) oder der
            // Nutzer ist kein Mitglied mehr - beides führt hierher zurück.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (Navigator.of(context).canPop()) Navigator.of(context).pop();
            });
            return const SizedBox.shrink();
          }
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Center(
                child: UserAvatar(name: group.name, profilePicture: group.photoUrl, radius: 48),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(group.name, style: Theme.of(context).textTheme.headlineSmall),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => GroupSwipeScreen(groupId: groupId)),
                      ),
                      style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
                      icon: const Icon(Icons.movie_filter_outlined),
                      label: const Text('Filme swipen'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => GroupChatScreen(groupId: groupId)),
                      ),
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: const Text('Chat'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              Text('Matches', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              _MatchesSection(groupId: groupId),
              const SizedBox(height: 32),
              Text('Watchlist', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              _WatchlistSection(groupId: groupId),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Mitglieder', style: Theme.of(context).textTheme.titleMedium),
                  if (isAdmin)
                    TextButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => InviteFriendScreen(groupId: groupId)),
                      ),
                      icon: const Icon(Icons.person_add_alt_1, size: 18),
                      label: const Text('Einladen'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              members.when(
                data: (members) => Column(
                  children: [
                    for (final member in members)
                      _MemberTile(
                        groupId: groupId,
                        member: member,
                        isCallerAdmin: isAdmin,
                        isSelf: member.uid == myMembership?.uid,
                      ),
                  ],
                ),
                loading: () =>
                    const Center(child: CircularProgressIndicator(color: AppColors.accent)),
                error: (error, _) => const Text('Mitglieder konnten nicht geladen werden.'),
              ),
              const SizedBox(height: 32),
              if (myMembership != null) _LeaveOrDeleteButton(groupId: groupId, isAdmin: isAdmin),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.accent)),
        error: (error, _) => const Center(child: Text('Gruppe konnte nicht geladen werden.')),
      ),
    );
  }
}

class _MatchesSection extends ConsumerWidget {
  const _MatchesSection({required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matchesAsync = ref.watch(groupMatchesProvider(groupId));

    return matchesAsync.when(
      data: (matches) {
        if (matches.isEmpty) {
          return const Text(
            'Noch kein gemeinsamer Film.',
            style: TextStyle(color: AppColors.textSecondary),
          );
        }
        return SizedBox(
          height: 210,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: matches.length,
            separatorBuilder: (context, index) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final match = matches[index];
              return SizedBox(
                width: 140,
                child: MatchCard(
                  match: match,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => MovieDetailScreen(tmdbId: match.movieId)),
                  ),
                ),
              );
            },
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator(color: AppColors.accent)),
      error: (error, _) => const Text(
        'Matches konnten nicht geladen werden.',
        style: TextStyle(color: AppColors.textSecondary),
      ),
    );
  }
}

/// Gruppenweiter Watchlist-Abgleich: zeigt jeden Film, den mindestens ein
/// aktuelles Mitglied auf "Vielleicht später" gesetzt hat, mit einem Badge,
/// das anzeigt, ob nur der aktuelle User oder mehrere Mitglieder ihn
/// vorgemerkt haben. Rein persönliche Watchlist-Einträge pro Nutzer/Gruppe
/// (siehe `SwipeDecision.watchlist`), keine gruppenübergreifende Ansicht.
class _WatchlistSection extends ConsumerWidget {
  const _WatchlistSection({required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final watchlistAsync = ref.watch(groupWatchlistProvider(groupId));
    final myUid = ref.watch(authStateChangesProvider).value?.uid;
    final totalMembers = ref.watch(groupMembersProvider(groupId)).value?.length;
    final removeState = ref.watch(watchlistRemoveControllerProvider(groupId));
    final removingMovieId =
        ref.watch(watchlistRemoveControllerProvider(groupId).notifier).removingMovieId;

    ref.listen(watchlistRemoveControllerProvider(groupId), (previous, next) {
      next.whenOrNull(
        error: (error, _) => ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(translateGroupError(error)))),
      );
    });

    return watchlistAsync.when(
      data: (entries) {
        if (entries.isEmpty) {
          return const Text(
            'Noch keine Filme auf der Watchlist.',
            style: TextStyle(color: AppColors.textSecondary),
          );
        }
        return SizedBox(
          height: 210,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: entries.length,
            separatorBuilder: (context, index) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final entry = entries[index];
              final isOwnEntry = myUid != null && entry.memberUids.contains(myUid);
              final isOnlyMe = entry.memberUids.length == 1 && isOwnEntry;
              final badgeLabel = isOnlyMe
                  ? 'Du hast vorgemerkt'
                  : '${entry.memberUids.length}/${totalMembers ?? entry.memberUids.length} vorgemerkt';
              return SizedBox(
                width: 140,
                child: WatchlistCard(
                  movieId: entry.movieId,
                  badgeLabel: badgeLabel,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => MovieDetailScreen(tmdbId: entry.movieId)),
                  ),
                  onRemove: isOwnEntry
                      ? () => ref
                          .read(watchlistRemoveControllerProvider(groupId).notifier)
                          .remove(entry.movieId)
                      : null,
                  isRemoving: removeState.isLoading && removingMovieId == entry.movieId,
                ),
              );
            },
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator(color: AppColors.accent)),
      error: (error, _) => const Text(
        'Watchlist konnte nicht geladen werden.',
        style: TextStyle(color: AppColors.textSecondary),
      ),
    );
  }
}

class _MemberTile extends ConsumerWidget {
  const _MemberTile({
    required this.groupId,
    required this.member,
    required this.isCallerAdmin,
    required this.isSelf,
  });

  final String groupId;
  final GroupMember member;
  final bool isCallerAdmin;
  final bool isSelf;

  Future<void> _confirmRemove(BuildContext context, WidgetRef ref, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Mitglied entfernen'),
        content: Text('Möchtest du $name wirklich aus der Gruppe entfernen?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Abbrechen')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Entfernen', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      ref.read(groupActionControllerProvider.notifier).removeMember(groupId, member.uid);
    }
  }

  Future<void> _confirmTransferAdmin(BuildContext context, WidgetRef ref, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Admin übertragen'),
        content: Text('Möchtest du $name zum neuen Admin dieser Gruppe machen?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Abbrechen')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Übertragen'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      ref.read(groupActionControllerProvider.notifier).transferAdmin(groupId, member.uid);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(publicProfileProvider(member.uid));

    return profile.when(
      data: (profile) {
        if (profile == null) return const SizedBox.shrink();
        final canManage = isCallerAdmin && !isSelf;
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: UserAvatar(name: profile.name, profilePicture: profile.profilePicture, radius: 20),
          title: Text(profile.name),
          subtitle: Text(
            member.isAdmin ? 'Admin' : 'Mitglied',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          trailing: canManage
              ? PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: AppColors.textSecondary),
                  onSelected: (value) {
                    if (value == 'remove') _confirmRemove(context, ref, profile.name);
                    if (value == 'transfer') _confirmTransferAdmin(context, ref, profile.name);
                  },
                  itemBuilder: (context) => [
                    if (!member.isAdmin)
                      const PopupMenuItem(value: 'transfer', child: Text('Zum Admin machen')),
                    const PopupMenuItem(value: 'remove', child: Text('Aus Gruppe entfernen')),
                  ],
                )
              : null,
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (error, _) => const SizedBox.shrink(),
    );
  }
}

class _LeaveOrDeleteButton extends ConsumerWidget {
  const _LeaveOrDeleteButton({required this.groupId, required this.isAdmin});

  final String groupId;
  final bool isAdmin;

  Future<void> _confirmLeave(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Gruppe verlassen'),
        content: const Text('Möchtest du diese Gruppe wirklich verlassen?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Abbrechen')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Verlassen', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      ref.read(groupActionControllerProvider.notifier).leaveGroup(groupId);
      if (context.mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Gruppe löschen'),
        content: const Text(
          'Möchtest du diese Gruppe wirklich unwiderruflich löschen? Alle Mitgliedschaften und offenen Einladungen werden entfernt.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Abbrechen')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Löschen', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      ref.read(groupActionControllerProvider.notifier).deleteGroup(groupId);
      if (context.mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLoading = ref.watch(groupActionControllerProvider).isLoading;

    return Column(
      children: [
        OutlinedButton.icon(
          onPressed: isLoading ? null : () => _confirmLeave(context, ref),
          icon: const Icon(Icons.exit_to_app, color: Colors.redAccent),
          label: const Text('Gruppe verlassen', style: TextStyle(color: Colors.redAccent)),
        ),
        if (isAdmin) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: isLoading ? null : () => _confirmDelete(context, ref),
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            label: const Text('Gruppe löschen', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ],
    );
  }
}
