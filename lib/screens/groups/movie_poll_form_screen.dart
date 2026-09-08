import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../components/auth/primary_button.dart';
import '../../components/movies/match_card.dart';
import '../../models/movie_match.dart';
import '../../models/watch_provider_option.dart';
import '../../providers/match_provider.dart';
import '../../providers/movie_poll_action_controller.dart';
import '../../providers/tmdb_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/movie_poll_error_translator.dart';

/// Rein lokaler Entwurf eines Terminvorschlags innerhalb der Abstimmung -
/// entsteht als echtes `MoviePollOption`-Dokument erst beim Absenden des
/// gesamten Formulars.
class _OptionDraft {
  _OptionDraft(DateTime initialSchedule)
      : date = DateTime(initialSchedule.year, initialSchedule.month, initialSchedule.day),
        time = TimeOfDay(hour: initialSchedule.hour, minute: initialSchedule.minute);

  DateTime date;
  TimeOfDay time;
  int? platformId;
  int? movieId;

  DateTime get scheduledAt => DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

/// Erstellt eine Filmabend-Abstimmung (§21: "Filmabend-Abstimmung") mit
/// mehreren Terminvorschlägen und einer festen Deadline. Kein Bearbeiten
/// einer bestehenden Abstimmung (mit dem Produktverantwortlichen
/// abgestimmt: Optionen sind nach dem Anlegen unveränderlich, siehe
/// `firestore.rules`) - dieser Screen deckt ausschließlich das Anlegen ab.
class MoviePollFormScreen extends ConsumerStatefulWidget {
  const MoviePollFormScreen({super.key, required this.groupId});

  final String groupId;

  @override
  ConsumerState<MoviePollFormScreen> createState() => _MoviePollFormScreenState();
}

class _MoviePollFormScreenState extends ConsumerState<MoviePollFormScreen> {
  static const _minOptionCount = 2;

  late DateTime _deadlineDate;
  late TimeOfDay _deadlineTime;
  late List<_OptionDraft> _options;

  bool _didSubmit = false;

  @override
  void initState() {
    super.initState();
    final deadline = DateTime.now().add(const Duration(days: 3));
    _deadlineDate = DateTime(deadline.year, deadline.month, deadline.day);
    _deadlineTime = TimeOfDay(hour: deadline.hour, minute: deadline.minute);
    _options = [
      _OptionDraft(DateTime.now().add(const Duration(days: 4, hours: 20))),
      _OptionDraft(DateTime.now().add(const Duration(days: 5, hours: 20))),
    ];
  }

  DateTime get _deadline =>
      DateTime(_deadlineDate.year, _deadlineDate.month, _deadlineDate.day, _deadlineTime.hour, _deadlineTime.minute);

  Future<void> _pickDeadlineDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _deadlineDate.isBefore(now) ? now : _deadlineDate,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _deadlineDate = picked);
  }

  Future<void> _pickDeadlineTime() async {
    final picked = await showTimePicker(context: context, initialTime: _deadlineTime);
    if (picked != null) setState(() => _deadlineTime = picked);
  }

  Future<void> _pickOptionDate(int index) async {
    final now = DateTime.now();
    final option = _options[index];
    final picked = await showDatePicker(
      context: context,
      initialDate: option.date.isBefore(now) ? now : option.date,
      firstDate: now,
      lastDate: now.add(const Duration(days: 730)),
    );
    if (picked != null) setState(() => option.date = picked);
  }

  Future<void> _pickOptionTime(int index) async {
    final option = _options[index];
    final picked = await showTimePicker(context: context, initialTime: option.time);
    if (picked != null) setState(() => option.time = picked);
  }

  void _addOption() {
    setState(() => _options.add(_OptionDraft(DateTime.now().add(const Duration(days: 4, hours: 20)))));
  }

  void _removeOption(int index) {
    setState(() => _options.removeAt(index));
  }

  void _save() {
    for (final option in _options) {
      if (option.platformId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bitte wähle für jeden Terminvorschlag eine Plattform aus.')),
        );
        return;
      }
    }

    _didSubmit = true;
    ref.read(moviePollActionControllerProvider(widget.groupId).notifier).create(
          deadline: _deadline,
          options: _options
              .map((option) => (scheduledAt: option.scheduledAt, platformId: option.platformId!, movieId: option.movieId))
              .toList(),
        );
  }

  @override
  Widget build(BuildContext context) {
    final actionState = ref.watch(moviePollActionControllerProvider(widget.groupId));
    final isLoading = actionState.isLoading;
    final providersAsync = ref.watch(watchProviderListProvider);
    final matchesAsync = ref.watch(groupMatchesProvider(widget.groupId));

    ref.listen(moviePollActionControllerProvider(widget.groupId), (previous, next) {
      next.whenOrNull(
        error: (error, _) => ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(translateMoviePollError(error)))),
        data: (_) {
          if (_didSubmit) {
            _didSubmit = false;
            Navigator.of(context).pop();
          }
        },
      );
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Abstimmung erstellen')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const _SectionTitle('Deadline'),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: isLoading ? null : _pickDeadlineDate,
                    icon: const Icon(Icons.calendar_today_outlined),
                    label: Text(
                      '${_deadlineDate.day.toString().padLeft(2, '0')}.${_deadlineDate.month.toString().padLeft(2, '0')}.${_deadlineDate.year}',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: isLoading ? null : _pickDeadlineTime,
                    icon: const Icon(Icons.access_time_outlined),
                    label: Text(_deadlineTime.format(context)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            const _SectionTitle('Terminvorschläge'),
            for (var index = 0; index < _options.length; index++) ...[
              _OptionEditor(
                option: _options[index],
                isLoading: isLoading,
                providersAsync: providersAsync,
                matchesAsync: matchesAsync,
                onPickDate: () => _pickOptionDate(index),
                onPickTime: () => _pickOptionTime(index),
                onPlatformChanged: (id) => setState(() => _options[index].platformId = id),
                onMovieChanged: (id) => setState(() => _options[index].movieId = id),
                onRemove: _options.length > _minOptionCount && !isLoading ? () => _removeOption(index) : null,
              ),
              const SizedBox(height: 16),
            ],
            OutlinedButton.icon(
              onPressed: isLoading ? null : _addOption,
              icon: const Icon(Icons.add),
              label: const Text('Terminvorschlag hinzufügen'),
            ),
            const SizedBox(height: 36),
            PrimaryButton(label: 'Abstimmung starten', isLoading: isLoading, onPressed: _save),
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

class _OptionEditor extends StatelessWidget {
  const _OptionEditor({
    required this.option,
    required this.isLoading,
    required this.providersAsync,
    required this.matchesAsync,
    required this.onPickDate,
    required this.onPickTime,
    required this.onPlatformChanged,
    required this.onMovieChanged,
    required this.onRemove,
  });

  final _OptionDraft option;
  final bool isLoading;
  final AsyncValue<List<WatchProviderOption>> providersAsync;
  final AsyncValue<List<MovieMatch>> matchesAsync;
  final VoidCallback onPickDate;
  final VoidCallback onPickTime;
  final ValueChanged<int?> onPlatformChanged;
  final ValueChanged<int?> onMovieChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: isLoading ? null : onPickDate,
                    icon: const Icon(Icons.calendar_today_outlined),
                    label: Text(
                      '${option.date.day.toString().padLeft(2, '0')}.${option.date.month.toString().padLeft(2, '0')}.${option.date.year}',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: isLoading ? null : onPickTime,
                    icon: const Icon(Icons.access_time_outlined),
                    label: Text(option.time.format(context)),
                  ),
                ),
                if (onRemove != null)
                  IconButton(
                    onPressed: onRemove,
                    icon: const Icon(Icons.close, color: AppColors.textSecondary),
                    tooltip: 'Terminvorschlag entfernen',
                  ),
              ],
            ),
            const SizedBox(height: 12),
            providersAsync.when(
              data: (providers) => Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final provider in providers)
                    ChoiceChip(
                      label: Text(provider.providerName),
                      selected: option.platformId == provider.providerId,
                      onSelected: isLoading ? null : (_) => onPlatformChanged(provider.providerId),
                    ),
                ],
              ),
              loading: () => const Center(child: CircularProgressIndicator(color: AppColors.accent)),
              error: (error, _) => const Text(
                'Plattformen konnten nicht geladen werden.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(height: 12),
            matchesAsync.when(
              data: (matches) {
                if (matches.isEmpty) {
                  return const Text(
                    'Kein Film ausgewählt (optional).',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  );
                }
                return SizedBox(
                  height: 150,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: matches.length,
                    separatorBuilder: (context, index) => const SizedBox(width: 12),
                    itemBuilder: (context, index) {
                      final match = matches[index];
                      final selected = option.movieId == match.movieId;
                      return SizedBox(
                        width: 100,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: selected ? Border.all(color: AppColors.accent, width: 3) : null,
                          ),
                          child: MatchCard(
                            match: match,
                            onTap: isLoading
                                ? () {}
                                : () => onMovieChanged(selected ? null : match.movieId),
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
          ],
        ),
      ),
    );
  }
}
