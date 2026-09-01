import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../components/auth/primary_button.dart';
import '../../components/movies/match_card.dart';
import '../../models/movie_night.dart';
import '../../providers/match_provider.dart';
import '../../providers/movie_night_action_controller.dart';
import '../../providers/tmdb_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/movie_night_error_translator.dart';

/// Filmabend anlegen oder bearbeiten (§12: "Filmabend planen"). [existing]
/// `null` bedeutet Anlegen, sonst Bearbeiten desselben Dokuments. Kein
/// Voting/RSVP/Mehrfachauswahl - ein einzelner Terminvorschlag mit Datum,
/// Uhrzeit, Plattform und optional genau einem bereits gematchten Film.
class MovieNightFormScreen extends ConsumerStatefulWidget {
  const MovieNightFormScreen({super.key, required this.groupId, this.existing});

  final String groupId;
  final MovieNight? existing;

  @override
  ConsumerState<MovieNightFormScreen> createState() => _MovieNightFormScreenState();
}

class _MovieNightFormScreenState extends ConsumerState<MovieNightFormScreen> {
  late DateTime _date;
  late TimeOfDay _time;
  int? _platformId;
  int? _movieId;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final initialSchedule = existing?.scheduledAt ?? DateTime.now().add(const Duration(days: 1));
    _date = DateTime(initialSchedule.year, initialSchedule.month, initialSchedule.day);
    _time = TimeOfDay(hour: initialSchedule.hour, minute: initialSchedule.minute);
    _platformId = existing?.platformId;
    _movieId = existing?.movieId;
  }

  DateTime get _scheduledAt =>
      DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute);

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.isBefore(DateTime(now.year, now.month, now.day)) ? now : _date,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 730)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  void _save() {
    final platformId = _platformId;
    if (platformId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte wähle eine Plattform aus.')),
      );
      return;
    }

    final notifier = ref.read(movieNightActionControllerProvider(widget.groupId).notifier);
    final existing = widget.existing;
    if (existing == null) {
      notifier.create(scheduledAt: _scheduledAt, platformId: platformId, movieId: _movieId);
    } else {
      notifier.edit(
        movieNightId: existing.id,
        scheduledAt: _scheduledAt,
        platformId: platformId,
        movieId: _movieId,
      );
    }
  }

  Future<void> _confirmCancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Filmabend absagen'),
        content: const Text('Möchtest du diesen Filmabend wirklich absagen?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Zurück')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Absagen', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await ref
          .read(movieNightActionControllerProvider(widget.groupId).notifier)
          .cancel(widget.existing!.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final actionState = ref.watch(movieNightActionControllerProvider(widget.groupId));
    final isLoading = actionState.isLoading;
    final providersAsync = ref.watch(watchProviderListProvider);
    final matchesAsync = ref.watch(groupMatchesProvider(widget.groupId));

    ref.listen(movieNightActionControllerProvider(widget.groupId), (previous, next) {
      next.whenOrNull(
        error: (error, _) => ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(translateMovieNightError(error)))),
        data: (_) {
          // Nur nach einem tatsächlichen Abschluss (nicht beim initialen
          // `build()`-Leerzustand) automatisch schließen - analog zu
          // `EditProfileScreen`.
          if (previous?.isLoading ?? false) {
            Navigator.of(context).pop();
          }
        },
      );
    });

    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Filmabend bearbeiten' : 'Filmabend planen')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const _SectionTitle('Termin'),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: isLoading ? null : _pickDate,
                    icon: const Icon(Icons.calendar_today_outlined),
                    label: Text(
                      '${_date.day.toString().padLeft(2, '0')}.${_date.month.toString().padLeft(2, '0')}.${_date.year}',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: isLoading ? null : _pickTime,
                    icon: const Icon(Icons.access_time_outlined),
                    label: Text(_time.format(context)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            const _SectionTitle('Plattform'),
            providersAsync.when(
              data: (providers) => _PlatformPicker(
                providers: providers.map((p) => (id: p.providerId, name: p.providerName)).toList(),
                selectedId: _platformId,
                enabled: !isLoading,
                onChanged: (id) => setState(() => _platformId = id),
              ),
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator(color: AppColors.accent)),
              ),
              error: (error, _) => const Text(
                'Plattformen konnten nicht geladen werden.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(height: 28),
            const _SectionTitle('Film (optional)'),
            matchesAsync.when(
              data: (matches) {
                if (matches.isEmpty) {
                  return const Text(
                    'Noch kein gemeinsamer Film - der Filmabend kann trotzdem ohne Film geplant werden.',
                    style: TextStyle(color: AppColors.textSecondary),
                  );
                }
                return SizedBox(
                  height: 170,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: matches.length,
                    separatorBuilder: (context, index) => const SizedBox(width: 12),
                    itemBuilder: (context, index) {
                      final match = matches[index];
                      final selected = _movieId == match.movieId;
                      return SizedBox(
                        width: 110,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: selected ? Border.all(color: AppColors.accent, width: 3) : null,
                          ),
                          child: MatchCard(
                            match: match,
                            onTap: isLoading
                                ? () {}
                                : () => setState(
                                      () => _movieId = selected ? null : match.movieId,
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
                'Matches konnten nicht geladen werden.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(height: 36),
            PrimaryButton(
              label: _isEditing ? 'Speichern' : 'Filmabend planen',
              isLoading: isLoading,
              onPressed: _save,
            ),
            if (_isEditing) ...[
              const SizedBox(height: 12),
              TextButton(
                onPressed: isLoading ? null : _confirmCancel,
                child: const Text('Filmabend absagen', style: TextStyle(color: Colors.redAccent)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}

class _PlatformPicker extends StatelessWidget {
  const _PlatformPicker({
    required this.providers,
    required this.selectedId,
    required this.enabled,
    required this.onChanged,
  });

  final List<({int id, String name})> providers;
  final int? selectedId;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    if (providers.isEmpty) {
      return const Text(
        'Für diese Region sind keine Streaming-Anbieter bekannt.',
        style: TextStyle(color: AppColors.textSecondary),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final provider in providers)
          ChoiceChip(
            label: Text(provider.name),
            selected: selectedId == provider.id,
            onSelected: enabled ? (_) => onChanged(provider.id) : null,
          ),
      ],
    );
  }
}
