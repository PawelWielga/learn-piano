import 'package:flutter/material.dart';

import '../midi/midi_file_picker.dart';
import '../midi/midi_file_picker_factory.dart';
import '../midi/midi_parser.dart';
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

  MidiFile? _midi;
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
        throw const MidiFormatException('Wybierz plik z rozszerzeniem .mid lub .midi.');
      }
      final midi = _parser.parse(selected.bytes);
      if (!mounted) return;
      setState(() {
        _midi = midi;
        _fileName = selected.name;
      });
    } on MidiFormatException catch (error) {
      if (mounted) {
        setState(() {
          _midi = null;
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

    return Scaffold(
      appBar: AppBar(title: const Text('Import MIDI')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Icon(Icons.library_music, size: 64, color: theme.colorScheme.primary),
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
                  label: Text(_busy ? 'Wczytywanie…' : 'Wybierz plik .mid / .midi'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
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
                  Text('Ścieżki', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  for (final track in midi.tracks)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              track.name?.isNotEmpty == true
                                  ? track.name!
                                  : 'Ścieżka ${track.index + 1}',
                              style: theme.textTheme.titleMedium,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${track.notes.length} nut • '
                              '${track.notes.map((n) => n.channel).toSet().length} kanałów',
                            ),
                            if (track.notes.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Pierwsze nuty: '
                                '${track.notes.take(10).map((n) => PitchEstimate.nameForMidi(n.midiNote)).join(', ')}',
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  const Text(
                    'Import jest gotowy. Wybór partii do treningu i '
                    'sprawdzanie akordów dodamy w następnym kroku.',
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
