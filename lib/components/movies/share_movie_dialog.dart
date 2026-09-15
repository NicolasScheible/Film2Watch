import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/group_provider.dart';
import '../../providers/movie_share_controller.dart';
import '../../theme/app_theme.dart';
import '../../utils/chat_error_translator.dart';

/// Listet die eigenen Gruppen zur Auswahl, in welchen Gruppenchat ein Film
/// geteilt werden soll (§11: "Teilen von Filmkarten") - analog zu
/// `TrailerDialog.show`. Zeigt ausschließlich Gruppen, in denen der Nutzer
/// bereits Mitglied ist ([myGroupsProvider]); die eigentliche Durchsetzung
/// bleibt unabhängig davon serverseitig (Firestore Rules).
class ShareMovieDialog extends ConsumerWidget {
  const ShareMovieDialog({super.key, required this.movieId});

  final int movieId;

  static Future<void> show(BuildContext context, int movieId) {
    return showDialog<void>(
      context: context,
      builder: (_) => ShareMovieDialog(movieId: movieId),
    );
  }

  /// Teilt den Film in [groupId] und reagiert direkt auf das Ergebnis dieses
  /// einen Aufrufs (Erfolg schließt den Dialog, Fehler zeigt einen Snackbar
  /// und lässt den Dialog offen, damit eine andere Gruppe versucht werden
  /// kann). Bewusst kein `ref.listen` auf den Controller-Zustand: dessen
  /// eigener `AsyncNotifier.build()` durchläuft beim allerersten Aufbau
  /// selbst einen Loading→Data-Übergang, der sich von einem echten,
  /// erfolgreichen Teilen-Aufruf nicht unterscheiden ließe und den Dialog
  /// sofort nach dem Öffnen wieder schließen würde.
  Future<void> _share(BuildContext context, WidgetRef ref, String groupId) async {
    await ref.read(movieShareControllerProvider(movieId).notifier).shareToGroup(groupId);
    if (!context.mounted) return;

    final result = ref.read(movieShareControllerProvider(movieId));
    if (result.hasError) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(translateChatError(result.error!))));
      return;
    }
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Film wurde geteilt.')));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupsAsync = ref.watch(myGroupsProvider);
    final shareState = ref.watch(movieShareControllerProvider(movieId));
    final sharingGroupId =
        ref.watch(movieShareControllerProvider(movieId).notifier).sharingGroupId;

    return Dialog(
      backgroundColor: AppColors.surface,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('In Gruppenchat teilen', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              SizedBox(
                height: 320,
                child: groupsAsync.when(
                  data: (groups) {
                    if (groups.isEmpty) {
                      return const Center(
                        child: Text(
                          'Du bist noch in keiner Gruppe.',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      );
                    }
                    return ListView(
                      children: [
                        for (final group in groups)
                          ListTile(
                            title: Text(group.name),
                            trailing: shareState.isLoading && sharingGroupId == group.id
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : null,
                            onTap: shareState.isLoading
                                ? null
                                : () => _share(context, ref, group.id),
                          ),
                      ],
                    );
                  },
                  loading: () =>
                      const Center(child: CircularProgressIndicator(color: AppColors.accent)),
                  error: (error, _) => const Center(
                    child: Text(
                      'Gruppen konnten nicht geladen werden.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
