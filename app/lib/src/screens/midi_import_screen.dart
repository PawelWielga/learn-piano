import 'package:flutter/material.dart';

import '../midi/midi_file_picker.dart';
import '../midi/midi_file_picker_factory.dart';
import '../midi/midi_parser.dart';
import '../midi/melody_part_analyzer.dart';
import '../pitch/pitch_detector.dart';
import '../instrument/instrument_range.dart';
import '../instrument/instrument_range_store.dart';
import '../instrument/instrument_range_store_factory.dart';
import 'instrument_range_screen.dart';

class MidiImportScreen extends StatefulWidget {
  const MidiImportScreen({super.key, this.filePicker, this.rangeStore});

  /// Injectable so tests never open a native browser file dialog.
  final MidiFilePicker? filePicker;
  final InstrumentRangeStore? rangeStore;

  @override
  State<MidiImportScreen> createState() => _MidiImportScreenState();
}

class _MidiImportScreenState extends State<MidiImportScreen> {
  late final MidiFilePicker _picker;
  final MidiParser _parser = const MidiParser();
  final MelodyPartAnalyzer _analyzer = const MelodyPartAnalyzer();
  late final InstrumentRangeStore _rangeStore;
  InstrumentRange _instrumentRange = InstrumentRange.defaultRange;

  MidiFile? _midi;
  List<MelodyPart> _parts = const [];
  MelodySelection? _selection;
  String? _fileName;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _picker = widget.filePicker ?? createMidiFilePicker();
    _rangeStore = widget.rangeStore ?? createInstrumentRangeStore();
    _loadInstrumentRange();
  }

  Future<void> _loadInstrumentRange() async {
    try {
      final saved = await _rangeStore.load();
      if (mounted && saved != null) {
        setState(() => _instrumentRange = saved);
      }
    } catch (_) {
      // A blocked localStorage must not prevent local file import.
    }
  }

  Future<void> _openRangeSettings() async {
    final result = await Navigator.of(context).push<InstrumentRange>(
      MaterialPageRoute(
        builder: (_) => InstrumentRangeScreen(
          initialRange: _instrumentRange,
          selection: _selection,
          rangeStore: _rangeStore,
        ),
      ),
    );
    if (mounted && result != null) {
      setState(() => _instrumentRange = result);
    }
  }

  Future<void> _import() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final selected = await _picker.pick();
      if (selected == null || !mounted) return;

      // Browser accept filters are suggestions, not security boundaries.
      final lowerName = selected.name.toLowerCase();
      if (!lowerName.endsWith('.mid') && !lowerName.endsWith('.midi')) {
        throw const MidiFormatException(
          'Wybierz plik z rozszerzeniem .mid lub .midi.',
        );
      }
      final midi = _parser.parse(selected.bytes);
      if (!mounted) return;
      setState(() {
        _midi = midi;
        _parts = _analyzer.analyze(midi);
        _selection = null;
        _fileName = selected.name;
      });
    } on MidiFormatException catch (error) {
      if (mounted) {
        setState(() {
          _midi = null;
          _parts = const [];
          _selection = null;
          _fileName = null;
          _error = error.message;
        });
      }
    } on MidiFilePickException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Nie udało się wczytać pliku MIDI.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final midi = _midi;
    final selection = _selection;
    final rangeCheck = selection == null
        ? null
        : _instrumentRange.checkNotes(
            selection.notes.map((note) => note.midiNote),
          );

    return Scaffold(
      appBar: AppBar(title: const Text('Import MIDI')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Icon(
                  Icons.library_music,
                  size: 64,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'Wybierz swoją melodię',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Plik MIDI jest odczytywany tylko w przeglądarce. '
                  'Nie wysyłamy go na serwer ani nie zapisujemy.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  key: const Key('choose-midi-file'),
                  onPressed: _busy ? null : _import,
                  icon: const Icon(Icons.upload_file),
                  label: Text(
                    _busy ? 'Wczytywanie…' : 'Wybierz plik .mid / .midi',
                  ),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Standard MIDI typu 0 i 1, maksymalnie 2 MB. '
                  'Obsługiwany czas PPQ (nie SMPTE).',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 20),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      key: const Key('midi-import-error'),
                      style: TextStyle(color: theme.colorScheme.error),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
                if (midi != null) ...[
                  const SizedBox(height: 28),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      'Wczytano: ${_fileName!}',
                      key: const Key('midi-file-name'),
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Typ ${midi.format} • ${midi.tracks.length} ścieżek • '
                    '${midi.noteCount} nut • '
                    '${(midi.duration.inMilliseconds / 1000).toStringAsFixed(1)} s',
                    key: const Key('midi-file-summary'),
                  ),
                  Text(
                    'Rozdzielczość: ${midi.ticksPerQuarterNote} PPQ • '
                    'Zmiany tempa: ${midi.tempoChanges.length}',
                  ),
                  const SizedBox(height: 20),
                  if (selection != null)
                    Semantics(
                      liveRegion: true,
                      child: Card(
                        key: const Key('selected-melody'),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Wybrana melodia',
                                style: theme.textTheme.titleMedium,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${selection.part.displayName} • '
                                'kanał ${selection.part.channel + 1}',
                              ),
                              Text(
                                '${selection.notes.length} nut: '
                                '${PitchEstimate.nameForMidi(selection.part.minMidiNote)}–'
                                '${PitchEstimate.nameForMidi(selection.part.maxMidiNote)}',
                                key: const Key('selected-melody-range'),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Twój zakres: '
                                '${PitchEstimate.nameForMidi(_instrumentRange.low)}–'
                                '${PitchEstimate.nameForMidi(_instrumentRange.high)}',
                                key: const Key('selected-instrument-range'),
                              ),
                              const SizedBox(height: 5),
                              if (rangeCheck!.canPractice)
                                const Text(
                                  'Wszystkie nuty mieszczą się w zakresie. '
                                  'Melodia jest gotowa do kolejnego etapu.',
                                  key: Key('selected-range-ok'),
                                )
                              else
                                Text(
                                  'Poza zakresem instrumentu: '
                                  '${rangeCheck.outsideCount} nut. '
                                  'Zmień ustawienia klawiatury. '
                                  'Ta melodia jest na razie niegrywalna.',
                                  key: const Key('selected-range-blocked'),
                                  style: TextStyle(
                                    color: theme.colorScheme.error,
                                  ),
                                ),
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                key: const Key('selected-open-range'),
                                onPressed: _openRangeSettings,
                                icon: const Icon(Icons.tune),
                                label: const Text('Dostosuj klawiaturę'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  else
                    const Text(
                      'Wybierz jedną z partii jednogłosowych poniżej. '
                      'Akordy oraz perkusja nie są obsługiwane w treningu.',
                      key: Key('melody-selection-hint'),
                    ),
                  const SizedBox(height: 20),
                  Text('Ścieżki i kanały', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  for (final track in midi.tracks)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                              child: Text(
                                track.name?.trim().isNotEmpty == true
                                    ? track.name!.trim()
                                    : 'Ścieżka ${track.index + 1}',
                                style: theme.textTheme.titleMedium,
                              ),
                            ),
                            if (track.notes.isEmpty)
                              const Padding(
                                padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
                                child: Text(
                                  'Pusta ścieżka: brak nut do nauki.',
                                ),
                              ),
                            for (final part in _parts.where(
                              (part) => part.trackIndex == track.index,
                            ))
                              Semantics(
                                button: part.canPractice,
                                enabled: part.canPractice,
                                selected: selection?.part == part,
                                child: InkWell(
                                  key: Key(
                                    'melody-part-${part.trackIndex}-${part.channel}',
                                  ),
                                  onTap: part.canPractice
                                      ? () => setState(() {
                                          _selection = _analyzer.select(
                                            _parts,
                                            trackIndex: part.trackIndex,
                                            channel: part.channel,
                                          );
                                        })
                                      : null,
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      10,
                                      16,
                                      14,
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Icon(
                                          part.canPractice
                                              ? selection?.part == part
                                                    ? Icons.check_circle
                                                    : Icons
                                                          .radio_button_unchecked
                                              : Icons.block,
                                          color: part.canPractice
                                              ? theme.colorScheme.primary
                                              : theme.colorScheme.error,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Kanał ${part.channel + 1} • '
                                                '${part.notes.length} nut',
                                                style:
                                                    theme.textTheme.titleSmall,
                                              ),
                                              Text(
                                                'Zakres: '
                                                '${PitchEstimate.nameForMidi(part.minMidiNote)}–'
                                                '${PitchEstimate.nameForMidi(part.maxMidiNote)} • '
                                                '${(part.duration.inMilliseconds / 1000).toStringAsFixed(1)} s',
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                part.isPercussion
                                                    ? 'Perkusja: nieobsługiwana w nauce nut.'
                                                    : part.overlapCount > 0
                                                    ? 'Akordy/nakładające się nuty: '
                                                          '${part.overlapCount}. '
                                                          'Ta partia nie nadaje się do treningu.'
                                                    : 'Melodia jednogłosowa. Dotknij, aby wybrać.',
                                                key: Key(
                                                  'melody-status-${part.trackIndex}-${part.channel}',
                                                ),
                                              ),
                                              if (part.canPractice) ...[
                                                const SizedBox(height: 4),
                                                Text(
                                                  'Pierwsze nuty: '
                                                  '${part.notes.take(6).map((n) => PitchEstimate.nameForMidi(n.midiNote)).join(', ')}',
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  const Text(
                    'Po wyborze melodii możesz ustawić zakres swojej '
                    'klawiatury. Wizualizację klawiszy i trening dodamy później.',
                    key: Key('midi-next-step'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
