import 'package:flutter/material.dart';

import '../instrument/instrument_range.dart';
import '../instrument/instrument_range_store.dart';
import '../instrument/instrument_range_store_factory.dart';
import '../midi/melody_part_analyzer.dart';
import '../pitch/pitch_detector.dart';
import '../widgets/piano_keyboard.dart';

/// Configures the physical instrument independently of the MIDI player.
class InstrumentRangeScreen extends StatefulWidget {
  const InstrumentRangeScreen({
    super.key,
    this.initialRange,
    this.selection,
    this.rangeStore,
  });

  final InstrumentRange? initialRange;
  final MelodySelection? selection;
  final InstrumentRangeStore? rangeStore;

  @override
  State<InstrumentRangeScreen> createState() => _InstrumentRangeScreenState();
}

class _InstrumentRangeScreenState extends State<InstrumentRangeScreen> {
  late final InstrumentRangeStore _store;
  late int _low;
  late int _high;
  bool _busy = false;
  String? _storageWarning;

  @override
  void initState() {
    super.initState();
    _store = widget.rangeStore ?? createInstrumentRangeStore();
    final initial = widget.initialRange ?? InstrumentRange.defaultRange;
    _low = initial.low;
    _high = initial.high;
    if (widget.initialRange == null) _loadRange();
  }

  Future<void> _loadRange() async {
    try {
      final saved = await _store.load();
      if (!mounted || saved == null) return;
      setState(() {
        _low = saved.low;
        _high = saved.high;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _storageWarning = 'Przeglądarka nie udostępnia zapisanych ustawień.';
        });
      }
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    final range = InstrumentRange.tryCreate(_low, _high);
    if (range == null) return;

    setState(() {
      _busy = true;
      _storageWarning = null;
    });
    try {
      await _store.save(range);
      if (mounted) Navigator.of(context).pop(range);
    } catch (_) {
      if (mounted) {
        setState(() {
          _storageWarning =
              'Nie udało się zapisać zakresu na tym urządzeniu. '
              'Możesz użyć go tylko w tej sesji.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _useWithoutSaving() {
    final range = InstrumentRange.tryCreate(_low, _high);
    if (range != null) Navigator.of(context).pop(range);
  }

  Widget _pitchPicker({
    required String label,
    required String keyPrefix,
    required int value,
    required ValueChanged<int> onChange,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label),
        const SizedBox(height: 4),
        Row(
          children: [
            IconButton.outlined(
              key: Key('$keyPrefix-decrease'),
              tooltip: 'Obniż o półton',
              onPressed: value > 0 ? () => onChange(value - 1) : null,
              icon: const Icon(Icons.remove),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: DropdownButton<int>(
                key: Key('$keyPrefix-note'),
                isExpanded: true,
                value: value,
                items: [
                  for (var note = 0; note <= 127; note++)
                    DropdownMenuItem<int>(
                      value: note,
                      child: Text(
                        '${PitchEstimate.nameForMidi(note)} (MIDI $note)',
                      ),
                    ),
                ],
                onChanged: (next) {
                  if (next != null) onChange(next);
                },
              ),
            ),
            const SizedBox(width: 6),
            IconButton.outlined(
              key: Key('$keyPrefix-increase'),
              tooltip: 'Podwyższ o półton',
              onPressed: value < 127 ? () => onChange(value + 1) : null,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final range = InstrumentRange.tryCreate(_low, _high);
    final selection = widget.selection;
    final check = selection == null || range == null
        ? null
        : range.checkNotes(selection.notes.map((note) => note.midiNote));
    final examples = check?.distinctOutsideNotes
        .take(8)
        .map(PitchEstimate.nameForMidi)
        .join(', ');

    return Scaffold(
      appBar: AppBar(title: const Text('Zakres klawiatury')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  'Dopasuj do swojego instrumentu',
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Ustaw rzeczywisty najniższy i najwyższy klawisz. '
                  'Nie zmieniamy ani nie transponujemy nut w MIDI.',
                ),
                const SizedBox(height: 24),
                Text('Popularne zakresy', style: theme.textTheme.titleMedium),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final preset in KeyboardPreset.values)
                      ChoiceChip(
                        key: Key('range-preset-${preset.keys}'),
                        label: Text('${preset.keys} klawiszy'),
                        selected: range == preset.range,
                        onSelected: (_) => setState(() {
                          _low = preset.range.low;
                          _high = preset.range.high;
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                _pitchPicker(
                  label: 'Najniższy klawisz',
                  keyPrefix: 'range-low',
                  value: _low,
                  onChange: (value) => setState(() => _low = value),
                ),
                const SizedBox(height: 12),
                _pitchPicker(
                  label: 'Najwyższy klawisz',
                  keyPrefix: 'range-high',
                  value: _high,
                  onChange: (value) => setState(() => _high = value),
                ),
                const SizedBox(height: 16),
                if (range == null)
                  Text(
                    'Najniższy klawisz nie może być wyższy od najwyższego.',
                    key: const Key('range-invalid'),
                    style: TextStyle(color: theme.colorScheme.error),
                  )
                else
                  Text(
                    'Twój instrument: ${PitchEstimate.nameForMidi(range.low)}–'
                    '${PitchEstimate.nameForMidi(range.high)} '
                    '(${range.keyCount} klawiszy)',
                    key: const Key('range-summary'),
                    style: theme.textTheme.titleMedium,
                  ),
                if (range != null) ...[
                  const SizedBox(height: 16),
                  PianoKeyboard(range: range, showRangeLabel: false),
                ],
                const SizedBox(height: 18),
                if (selection != null && range != null) ...[
                  Text(
                    'Sprawdzenie melodii: ${selection.part.displayName}',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  if (check!.canPractice)
                    Text(
                      'Wszystkie ${selection.notes.length} nut mieszczą się '
                      'w zakresie klawiatury.',
                      key: const Key('range-playable'),
                    )
                  else
                    Text(
                      'Poza zakresem: ${check.outsideCount} z '
                      '${selection.notes.length} nut. '
                      'Przykłady: $examples'
                      '${check.distinctOutsideNotes.length > 8 ? ', …' : ''}. '
                      'Tej melodii nie można jeszcze ćwiczyć na '
                      'wybranej klawiaturze.',
                      key: const Key('range-outside-warning'),
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                ],
                if (_storageWarning != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _storageWarning!,
                    key: const Key('range-storage-warning'),
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                  if (range != null)
                    TextButton(
                      key: const Key('range-use-once'),
                      onPressed: _useWithoutSaving,
                      child: const Text('Użyj bez zapisywania'),
                    ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  key: const Key('range-save'),
                  onPressed: range == null || _busy ? null : _save,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                  ),
                  child: Text(_busy ? 'Zapisywanie…' : 'Zapisz zakres'),
                ),
                const SizedBox(height: 12),
                Text(
                  'Ustawienie zapisujemy wyłącznie lokalnie w przeglądarce. '
                  'Importowany plik MIDI nie jest zapisywany.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
