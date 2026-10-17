import 'dart:async';

import 'package:flutter/material.dart';

import '../audio/audio_file_picker.dart';
import '../audio/audio_file_picker_factory.dart';
import '../pitch/detection_preferences.dart';
import '../pitch/detection_preferences_store_factory.dart';
import '../pitch/pitch_detector.dart';
import '../recording/midi_recording_export.dart';
import '../recording/midi_recording_export_factory.dart';
import '../recording/midi_recording_writer.dart';
import '../transcription/transcription_engine.dart';
import '../transcription/transcription_engine_factory.dart';
import '../recording/note_recorder.dart';

/// Local-only multi-pitch MP3 transcription. No microphone or cloud service.
class Mp3ImportScreen extends StatefulWidget {
  const Mp3ImportScreen({
    super.key,
    this.picker,
    this.exporter,
    this.detectionPreferences,
    this.engine,
  });

  final AudioFilePicker? picker;
  final MidiRecordingExporter? exporter;
  final DetectionPreferences? detectionPreferences;
  final TranscriptionEngine? engine;

  @override
  State<Mp3ImportScreen> createState() => _Mp3ImportScreenState();
}

class _Mp3ImportScreenState extends State<Mp3ImportScreen> {
  late final AudioFilePicker _picker;
  late final TranscriptionEngine _engine;
  late final MidiRecordingExporter _exporter;
  late final DetectionPreferences _preferences;
  List<RecordedNote> _notes = const [];
  String? _filename;
  Duration? _duration;
  String? _error;
  String? _message;
  double _progress = 0;
  bool _busy = false;
  bool _pickerReady = true;
  bool _pickerLoading = false;
  bool _truncated = false;
  bool _hasPitchBends = false;
  String? _engineId;
  List<String> _limitations = const [];
  TranscriptionMode _mode = TranscriptionMode.accurate;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _picker = widget.picker ?? createAudioFilePicker();
    _engine = widget.engine ?? createTranscriptionEngine();
    _exporter = widget.exporter ?? createMidiRecordingExporter();
    if (_picker is PreparableAudioFilePicker) {
      _pickerReady = false;
      unawaited(_preparePicker());
    }
    try {
      _preferences =
          widget.detectionPreferences ??
          createDetectionPreferencesStore().load() ??
          const DetectionPreferences();
    } catch (_) {
      _preferences = const DetectionPreferences();
    }
  }

  Future<void> _preparePicker() async {
    if (_pickerLoading || _picker is! PreparableAudioFilePicker) return;
    setState(() {
      _pickerLoading = true;
      _error = null;
    });
    try {
      await (_picker as PreparableAudioFilePicker).prepare();
      if (mounted) setState(() => _pickerReady = true);
    } on AudioFilePickException catch (exception) {
      if (mounted) setState(() => _error = exception.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Nie można załadować wyboru MP3. Odśwież stronę.',
        );
      }
    } finally {
      if (mounted) setState(() => _pickerLoading = false);
    }
  }

  Future<void> _chooseMp3() async {
    if (_busy || !_pickerReady) return;
    final request = ++_request;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
      _progress = 0;
    });
    try {
      final audio = await _picker.pickAndDecode();
      if (!mounted || request != _request || audio == null) return;
      setState(() {
        _notes = const [];
        _filename = audio.name;
        _duration = audio.duration;
        _truncated = false;
        _hasPitchBends = false;
        _engineId = null;
        _limitations = const [];
      });
      final result = await _engine.transcribe(
        audio,
        options: TranscriptionOptions(preferences: _preferences, mode: _mode),
        isCancelled: () => !mounted || request != _request,
        onProgress: (progress) {
          if (mounted && request == _request && progress.isFinite && _busy) {
            setState(() => _progress = progress.clamp(0.0, 1.0));
          }
        },
      );
      if (!mounted || request != _request) return;
      final normalized = result.toRecordedNotes();
      if (!mounted || request != _request) return;
      setState(() {
        _notes = normalized;
        _duration = result.duration;
        _truncated = result.truncated;
        _hasPitchBends = result.hasPitchBends;
        _engineId = result.engineId;
        _limitations = List<String>.unmodifiable(result.limitations);
        _message = normalized.isEmpty
            ? 'Nie wykryto nut. Spróbuj dokładnej analizy lub zwiększ '
                  'czułość w ustawieniach.'
            : 'Rozpoznano ${normalized.length} nut. '
                  'Sprawdź wynik odsłuchem po imporcie MIDI.';
      });
    } on TranscriptionCancelled {
      // Leaving this screen invalidates the work. Do not retain PCM.
    } on AudioFilePickException catch (exception) {
      if (mounted && request == _request) {
        setState(() => _error = exception.message);
      }
    } on FormatException catch (exception) {
      if (mounted && request == _request) {
        setState(() => _error = exception.message);
      }
    } catch (_) {
      if (mounted && request == _request) {
        setState(() => _error = 'Nie udało się przeanalizować pliku MP3.');
      }
    } finally {
      if (mounted && request == _request) {
        setState(() => _busy = false);
      }
    }
  }

  void _cancelAnalysis() {
    if (!_busy) return;
    // Invalidates the running analysis; its next checkpoint stops the work.
    ++_request;
    setState(() {
      _busy = false;
      _progress = 0;
      _message = 'Analiza anulowana.';
    });
  }

  void _saveMidi() {
    if (_busy || _notes.isEmpty) return;
    try {
      final bytes = const MidiRecordingWriter().write(_notes);
      final ok = _exporter.save(
        bytes,
        'learn-piano-mp3-${DateTime.now().millisecondsSinceEpoch}.mid',
      );
      setState(() {
        _error = ok ? null : 'Nie można pobrać pliku MIDI.';
        _message = ok ? 'Rozpoczęto pobieranie MIDI.' : null;
      });
    } catch (_) {
      setState(() => _error = 'Nie udało się utworzyć pliku MIDI.');
    }
  }

  @override
  void dispose() {
    _request++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Odczytaj nuty z MP3')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('MP3 → MIDI', style: theme.textTheme.headlineSmall),
                const SizedBox(height: 8),
                const Text(
                  'Wybierz nagranie pianina. Analiza lokalna spróbuje '
                  'odczytać jednoczesne nuty melodii i akompaniamentu. '
                  'Nie używamy mikrofonu ani serwera.',
                ),
                const SizedBox(height: 12),
                const Text(
                  'Limit: 12 MB i 90 sekund. Rozpoznawanie nut jest '
                  'przybliżone, szczególnie przy gęstych akordach, '
                  'perkusji i pogłosie. Czasy naciśnięć i zwolnień '
                  'są szacowane.',
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  children: [
                    ChoiceChip(
                      key: const Key('mp3-mode-fast'),
                      label: const Text('Szybka'),
                      selected: _mode == TranscriptionMode.fast,
                      onSelected: _busy
                          ? null
                          : (_) =>
                                setState(() => _mode = TranscriptionMode.fast),
                    ),
                    ChoiceChip(
                      key: const Key('mp3-mode-accurate'),
                      label: const Text('Dokładna (wielogłosowa)'),
                      selected: _mode == TranscriptionMode.accurate,
                      onSelected: _busy
                          ? null
                          : (_) => setState(
                              () => _mode = TranscriptionMode.accurate,
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      key: const Key('mp3-select'),
                      onPressed: _busy || _pickerLoading
                          ? null
                          : _pickerReady
                          ? _chooseMp3
                          : _preparePicker,
                      icon: const Icon(Icons.audio_file),
                      label: Text(
                        _pickerLoading
                            ? 'Przygotowywanie wyboru…'
                            : !_pickerReady
                            ? 'Ponów przygotowanie wyboru MP3'
                            : _busy
                            ? 'Analizowanie…'
                            : 'Wybierz plik MP3',
                      ),
                    ),
                    if (_busy)
                      OutlinedButton.icon(
                        key: const Key('mp3-cancel'),
                        onPressed: _cancelAnalysis,
                        icon: const Icon(Icons.close),
                        label: const Text('Anuluj analizę'),
                      ),
                    OutlinedButton.icon(
                      key: const Key('mp3-save'),
                      onPressed: _busy || _notes.isEmpty ? null : _saveMidi,
                      icon: const Icon(Icons.download),
                      label: const Text('Zapisz MIDI'),
                    ),
                  ],
                ),
                if (_busy) ...[
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    key: const Key('mp3-progress'),
                    value: _progress,
                  ),
                  const SizedBox(height: 4),
                  Text('Analiza: ${(_progress * 100).round()}%'),
                ],
                if (_filename != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Plik: $_filename (${_duration?.inSeconds ?? 0} s)',
                    key: const Key('mp3-selected-name'),
                  ),
                ],
                const SizedBox(height: 10),
                Text(
                  'Rozpoznane nuty: ${_notes.length}',
                  key: const Key('mp3-note-count'),
                  style: theme.textTheme.titleMedium,
                ),
                if (_engineId != null) Text('Silnik: $_engineId'),
                for (final limitation in _limitations) Text(limitation),
                if (_hasPitchBends)
                  const Text(
                    'Uwaga: eksport MIDI nie zapisuje odstrojeń '
                    'wysokości (pitch bends).',
                    key: Key('mp3-pitch-bend-warning'),
                  ),
                if (_notes.isNotEmpty)
                  Text(
                    'Zakres: ${PitchEstimate.nameForMidi(_notes.map((n) => n.midiNote).reduce((a, b) => a < b ? a : b))}'
                    ' – ${PitchEstimate.nameForMidi(_notes.map((n) => n.midiNote).reduce((a, b) => a > b ? a : b))}',
                    key: const Key('mp3-note-range'),
                  ),
                if (_truncated)
                  const Text(
                    'Wynik jest niepełny: silnik osiągnął swój limit nut.',
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    key: const Key('mp3-error'),
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
                if (_message != null) ...[
                  const SizedBox(height: 8),
                  Text(_message!, key: const Key('mp3-message')),
                ],
                const SizedBox(height: 18),
                if (_notes.isNotEmpty) ...[
                  Text('Podgląd nut', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final note in _notes.take(32))
                        Chip(
                          label: Text(
                            '${PitchEstimate.nameForMidi(note.midiNote)} '
                            '${note.start.inMilliseconds}–'
                            '${(note.start + note.duration).inMilliseconds} ms',
                          ),
                        ),
                    ],
                  ),
                  if (_notes.length > 32)
                    Text('Wyświetlono pierwsze 32 z ${_notes.length} nut.'),
                  const SizedBox(height: 14),
                  const Text(
                    'Plik możesz ponownie zaimportować przez „Importuj plik MIDI”. '
                    'Współbrzmienia obejrzysz w podglądzie wielogłosowym. '
                    'Trening Wait for Note nadal wymaga partii jednogłosowej.',
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
