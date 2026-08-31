import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../components/auth/primary_button.dart';
import '../../models/movie_filter.dart';
import '../../models/watch_provider_option.dart';
import '../../providers/movie_filter_provider.dart';
import '../../providers/tmdb_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/tmdb_error_translator.dart';

/// Bearbeitet die [MovieFilter]-Auswahl einer Gruppen-Swipe-Session (§10 der
/// Master-Spezifikation). Rein lokaler Bearbeitungs-State bis "Anwenden"
/// gedrückt wird - Abbrechen (Zurück-Button) verwirft Änderungen, ohne den
/// bereits aktiven Filter der Session zu verändern.
class MovieFilterScreen extends ConsumerStatefulWidget {
  const MovieFilterScreen({super.key, required this.groupId});

  final String groupId;

  @override
  ConsumerState<MovieFilterScreen> createState() => _MovieFilterScreenState();
}

class _MovieFilterScreenState extends ConsumerState<MovieFilterScreen> {
  late MovieFilter _draft;

  static final _minYear = 1900;
  static final _maxYear = DateTime.now().year;
  static const _maxRuntimeMinutes = 240;

  @override
  void initState() {
    super.initState();
    _draft = ref.read(movieFilterControllerProvider(widget.groupId));
  }

  void _apply() {
    ref.read(movieFilterControllerProvider(widget.groupId).notifier).update(_draft);
    Navigator.of(context).pop();
  }

  void _reset() {
    setState(() => _draft = MovieFilter.empty);
  }

  @override
  Widget build(BuildContext context) {
    final genresAsync = ref.watch(movieGenresProvider);
    final providersAsync = ref.watch(watchProviderListProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Filter'),
        actions: [
          TextButton(
            onPressed: _draft.isActive ? _reset : null,
            child: const Text('Zurücksetzen'),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          children: [
            _SectionTitle('Plattform'),
            providersAsync.when(
              data: (providers) => _PlatformSelector(
                providers: providers,
                selectedId: _draft.watchProviderId,
                onChanged: (id) => setState(
                  () => _draft = id == null
                      ? _draft.copyWith(clearWatchProviderId: true)
                      : _draft.copyWith(watchProviderId: id),
                ),
              ),
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator(color: AppColors.accent)),
              ),
              error: (error, _) => _FilterErrorHint(translateTmdbError(error)),
            ),
            const SizedBox(height: 28),
            _SectionTitle('Genre'),
            genresAsync.when(
              data: (genres) => _GenreSelector(
                genres: genres,
                selectedIds: _draft.genreIds,
                onChanged: (ids) => setState(() => _draft = _draft.copyWith(genreIds: ids)),
              ),
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator(color: AppColors.accent)),
              ),
              error: (error, _) => _FilterErrorHint(translateTmdbError(error)),
            ),
            const SizedBox(height: 28),
            _SectionTitle('Erscheinungsjahr'),
            _YearRangeSelector(
              min: _minYear,
              max: _maxYear,
              from: _draft.yearFrom,
              to: _draft.yearTo,
              onChanged: (from, to) => setState(
                () => _draft = _draft.copyWith(
                  yearFrom: from,
                  clearYearFrom: from == null,
                  yearTo: to,
                  clearYearTo: to == null,
                ),
              ),
            ),
            const SizedBox(height: 28),
            _SectionTitle('Mindestbewertung'),
            _MinRatingSelector(
              value: _draft.minRating ?? 0,
              onChanged: (value) => setState(
                () => _draft = value <= 0
                    ? _draft.copyWith(clearMinRating: true)
                    : _draft.copyWith(minRating: value),
              ),
            ),
            const SizedBox(height: 28),
            _SectionTitle('Filmlänge'),
            _RuntimeRangeSelector(
              max: _maxRuntimeMinutes,
              from: _draft.runtimeFromMinutes,
              to: _draft.runtimeToMinutes,
              onChanged: (from, to) => setState(
                () => _draft = _draft.copyWith(
                  runtimeFromMinutes: from,
                  clearRuntimeFromMinutes: from == null,
                  runtimeToMinutes: to,
                  clearRuntimeToMinutes: to == null,
                ),
              ),
            ),
            const SizedBox(height: 36),
            PrimaryButton(label: 'Anwenden', onPressed: _apply),
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
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

class _FilterErrorHint extends StatelessWidget {
  const _FilterErrorHint(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Text(message, style: const TextStyle(color: AppColors.textSecondary));
  }
}

class _PlatformSelector extends StatelessWidget {
  const _PlatformSelector({
    required this.providers,
    required this.selectedId,
    required this.onChanged,
  });

  final List<WatchProviderOption> providers;
  final int? selectedId;
  final ValueChanged<int?> onChanged;

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
        ChoiceChip(
          label: const Text('Alle'),
          selected: selectedId == null,
          onSelected: (_) => onChanged(null),
        ),
        for (final provider in providers)
          ChoiceChip(
            label: Text(provider.providerName),
            selected: selectedId == provider.providerId,
            onSelected: (_) => onChanged(provider.providerId),
          ),
      ],
    );
  }
}

class _GenreSelector extends StatelessWidget {
  const _GenreSelector({
    required this.genres,
    required this.selectedIds,
    required this.onChanged,
  });

  final Map<int, String> genres;
  final Set<int> selectedIds;
  final ValueChanged<Set<int>> onChanged;

  @override
  Widget build(BuildContext context) {
    if (genres.isEmpty) {
      return const Text(
        'Genres konnten nicht geladen werden.',
        style: TextStyle(color: AppColors.textSecondary),
      );
    }
    final sortedEntries = genres.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final entry in sortedEntries)
          FilterChip(
            label: Text(entry.value),
            selected: selectedIds.contains(entry.key),
            onSelected: (selected) {
              final next = Set<int>.from(selectedIds);
              if (selected) {
                next.add(entry.key);
              } else {
                next.remove(entry.key);
              }
              onChanged(next);
            },
          ),
      ],
    );
  }
}

class _YearRangeSelector extends StatelessWidget {
  const _YearRangeSelector({
    required this.min,
    required this.max,
    required this.from,
    required this.to,
    required this.onChanged,
  });

  final int min;
  final int max;
  final int? from;
  final int? to;
  final void Function(int? from, int? to) onChanged;

  @override
  Widget build(BuildContext context) {
    final values = RangeValues(
      (from ?? min).toDouble(),
      (to ?? max).toDouble(),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${values.start.round()} – ${values.end.round()}',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        RangeSlider(
          min: min.toDouble(),
          max: max.toDouble(),
          divisions: max - min,
          values: values,
          activeColor: AppColors.accent,
          labels: RangeLabels('${values.start.round()}', '${values.end.round()}'),
          onChanged: (next) {
            final nextFrom = next.start.round();
            final nextTo = next.end.round();
            onChanged(
              nextFrom == min ? null : nextFrom,
              nextTo == max ? null : nextTo,
            );
          },
        ),
      ],
    );
  }
}

class _MinRatingSelector extends StatelessWidget {
  const _MinRatingSelector({required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value <= 0 ? 'Keine Mindestbewertung' : 'Mindestens ${value.toStringAsFixed(1)}',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        Slider(
          min: 0,
          max: 10,
          divisions: 20,
          value: value,
          activeColor: AppColors.accent,
          label: value.toStringAsFixed(1),
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _RuntimeRangeSelector extends StatelessWidget {
  const _RuntimeRangeSelector({
    required this.max,
    required this.from,
    required this.to,
    required this.onChanged,
  });

  final int max;
  final int? from;
  final int? to;
  final void Function(int? from, int? to) onChanged;

  @override
  Widget build(BuildContext context) {
    final values = RangeValues(
      (from ?? 0).toDouble(),
      (to ?? max).toDouble(),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${values.start.round()} – ${values.end.round()} Minuten',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        RangeSlider(
          min: 0,
          max: max.toDouble(),
          divisions: max ~/ 10,
          values: values,
          activeColor: AppColors.accent,
          labels: RangeLabels('${values.start.round()}', '${values.end.round()}'),
          onChanged: (next) {
            final nextFrom = next.start.round();
            final nextTo = next.end.round();
            onChanged(
              nextFrom == 0 ? null : nextFrom,
              nextTo == max ? null : nextTo,
            );
          },
        ),
      ],
    );
  }
}
