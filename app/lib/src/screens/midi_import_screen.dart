import 'package:flutter/material.dart';

import '../midi/midi_file_picker.dart';
import '../midi/midi_file_picker_factory.dart';
import '../midi/midi_parser.dart';
import '../midi/melody_part_analyzer.dart';
import '../pitch/pitch_detector.dart';

class MidiImportScreen extends StatefulWidget {
  const MidiImportScreen({super.key, this.filePicker});

  /// Injectable so tests never open a native browser file dialog.
  final MidiFilePicker? filePicker;

  @override
  State<MidiImportScreen> createState() => _MidiImportScreenState();
}

class _MidiImportScreenState extends State<MidiImportScreen> {
  late final MidiFilePicker _picker;
  final MidiParser _parser = const MidiParser();
  final MelodyPartAnalyzer _analyzer = const MelodyPartAnalyzer();

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
                              const Text(
                                'Partia jednogłosowa. Gotowa do następnego '
                                'etapu: konfiguracji zakresu instrumentu.',
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
                                child: Text('Pusta ścieżka: brak nut do nauki.'),
                              ),
                            for (final part in _parts.where(
                              (part) => part.trackIndex == track.index,
                            ))
                              ListTile(
                                key: Key(
                                  'melody-part-${part.trackIndex}-${part.channel}',
                                ),
                                enabled: part.canPractice,
                                selected: selection?.part == part,
                                onTap: part.canPractice
                                    ? () => setState(() {
                                        _selection = _analyzer.select(
                                          _parts,
                                          trackIndex: part.trackIndex,
                                          channel: part.channel,
                                        );
                                      })
                                    : null,
                                leading: Icon(
                                  part.canPractice
                                      ? selection?.part == part
                                          ? Icons.check_circle
                                          : Icons.radio_button_unchecked
                                      : Icons.block,
                                ),
                                title: Text(
                                  'Kanał ${part.channel + 1} • '
                                  '${part.notes.length} nut',
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Zakres: '
                                      '${PitchEstimate.nameForMidi(part.minMidiNote)}–'
                                      '${PitchEstimate.nameForMidi(part.maxMidiNote)} • '
                                      '${(part.duration.inMilliseconds / 1000).toStringAsFixed(1)} s',
                                    ),
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
                                    if (part.canPractice)
                                      Text(
                                        'Pierwsze nuty: '
                                        '${part.notes.take(6).map((n) => PitchEstimate.nameForMidi(n.midiNote)).join(', ')}',
                                      ),
                                  ],
                                ),
                                isThreeLine: true,
                              ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  const Text(
                    'Po wyborze melodii następnym krokiem będzie ustawienie '
                    'zakresu fizycznej klawiatury. Trening dodamy później.',
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
