import 'dart:async';

import 'package:flutter/material.dart';

import '../audio/audio_input.dart';
import '../audio/audio_input_factory.dart';
import '../audio/note_output.dart';
import '../audio/note_output_factory.dart';
import '../instrument/instrument_range.dart';
import '../instrument/instrument_range_store.dart';
import '../instrument/instrument_range_store_factory.dart';
import '../pitch/detection_preferences.dart';
import '../pitch/detection_preferences_store_factory.dart';
import '../pitch/note_event_tracker.dart';
import '../pitch/pitch_detector.dart';
import '../recording/midi_recording_export.dart';
import '../recording/midi_recording_export_factory.dart';
import '../recording/midi_recording_writer.dart';
import '../recording/note_recorder.dart';
import '../training/training_input_mode.dart';
import '../widgets/recording_keyboard.dart';

/// Free recording: acoustic monophonic notes or polyphonic screen keyboard.
/// Keeps only note events, never raw microphone audio.
class RecordingScreen extends StatefulWidget {
  const RecordingScreen({
    super.key,
    this.audioInput,
    this.noteOutput,
    this.exporter,
    this.rangeStore,
    this.detectionPreferences,
  });

  final AudioInput? audioInput;
  final NoteOutput? noteOutput;
  final MidiRecordingExporter? exporter;
  final InstrumentRangeStore? rangeStore;
  final DetectionPreferences? detectionPreferences;

  @override
  State<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends State<RecordingScreen>
    with WidgetsBindingObserver {
  late final AudioInput _input;
  late final NoteOutput _output;
  late final MidiRecordingExporter _exporter;
  final NoteRecorder _recorder = NoteRecorder();
  late final PitchDetector _detector;
  late final NoteEventTracker _tracker;
  final Stopwatch _keyboardClock = Stopwatch();
  final Set<int> _heldKeys = {};
  StreamSubscription<PcmFrame>? _frames;
  StreamSubscription<AudioInputStatus>? _statuses;

  InstrumentRange _range = InstrumentRange.defaultRange;
  TrainingInputMode _mode = TrainingInputMode.microphone;
  bool _recording = false;
  bool _listening = false;
  bool _busy = false;
  int _startRequestId = 0;
  int? _stableNote;
  Duration? _micOrigin;
  Duration? _lastAnalyzedAt;
  Duration _micElapsed = Duration.zero;
  String? _message;
  String? _error;

  @override
  void initState() {
    super.initState();
    _input = widget.audioInput ?? createAudioInput();
    _output = widget.noteOutput ?? createNoteOutput();
    _exporter = widget.exporter ?? createMidiRecordingExporter();
    DetectionPreferences preferences;
    try {
      preferences =
          widget.detectionPreferences ??
          createDetectionPreferencesStore().load() ??
          const DetectionPreferences();
    } catch (_) {
      preferences = const DetectionPreferences();
    }
    _detector = preferences.createDetector();
    _tracker = preferences.createTracker();
    WidgetsBinding.instance.addObserver(this);
    _frames = _input.frames.listen(_onFrame);
    _statuses = _input.statuses.listen(_onStatus);
    unawaited(_loadRange());
  }

  Future<void> _loadRange() async {
    try {
      final saved = await (widget.rangeStore ?? createInstrumentRangeStore())
          .load();
      if (mounted && saved != null) setState(() => _range = saved);
    } catch (_) {
      // Browser storage is optional.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _recording) {
      unawaited(_stop(message: 'Nagrywanie zatrzymane po zmianie karty.'));
    }
  }

  void _onStatus(AudioInputStatus status) {
    if (!_listening || !_recording || status == AudioInputStatus.listening) {
      return;
    }
    unawaited(
      _stop(message: 'Mikrofon został przerwany. Zapisz zebrane nuty.'),
    );
  }

  void _onFrame(PcmFrame frame) {
    if (!mounted ||
        !_recording ||
        !_listening ||
        _busy ||
        frame.samples.isEmpty) {
      return;
    }
    _micOrigin ??= frame.capturedAt;
    final relative = frame.capturedAt - _micOrigin!;
    _micElapsed = relative.isNegative ? Duration.zero : relative;
    final previous = _lastAnalyzedAt;
    if (previous != null &&
        frame.capturedAt >= previous &&
        frame.capturedAt - previous < const Duration(milliseconds: 120)) {
      return;
    }
    _lastAnalyzedAt = frame.capturedAt;
    final update = _tracker.observe(
      _detector.detect(frame.samples, frame.sampleRate),
      frame.capturedAt,
    );
    for (final event in update.events) {
      final at = event.at - _micOrigin!;
      if (event.type == NoteEventType.noteOn) {
        _recorder.noteOn(event.midiNote, at);
      } else {
        _recorder.noteOff(event.midiNote, at);
      }
    }
    setState(() => _stableNote = update.stableNote);
  }

  Future<void> _start() async {
    if (_busy || _recording) return;
    final request = ++_startRequestId;
    setState(() {
      _error = null;
      _message = null;
      _stableNote = null;
      _micOrigin = null;
      _lastAnalyzedAt = null;
      _micElapsed = Duration.zero;
      _tracker.reset();
    });
    if (_mode == TrainingInputMode.keyboard) {
      _recorder.start();
      _keyboardClock
        ..reset()
        ..start();
      setState(() => _recording = true);
      return;
    }
    setState(() => _busy = true);
    try {
      await _input.start();
      if (!mounted || request != _startRequestId) {
        await _input.stop();
        return;
      }
      _recorder.start();
      setState(() {
        _recording = true;
        _listening = true;
      });
    } on AudioInputException catch (error) {
      if (mounted && request == _startRequestId) {
        setState(() => _error = _audioError(error.failure));
      }
    } catch (_) {
      if (mounted && request == _startRequestId) {
        setState(() => _error = 'Nie udało się uruchomić mikrofonu.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop({String? message}) async {
    if (!_recording || _busy) return;
    final wasListening = _listening;
    _startRequestId++;
    final at = wasListening ? _micElapsed : _keyboardClock.elapsed;
    _recorder.stop(at);
    _keyboardClock.stop();
    _heldKeys.clear();
    _output.stopAll();
    _tracker.reset();
    setState(() {
      _recording = false;
      _listening = false;
      _stableNote = null;
      _busy = wasListening;
      _message = message ?? 'Nagranie zakończone. Możesz zapisać MIDI.';
    });
    if (wasListening) {
      try {
        await _input.stop();
      } catch (_) {
        if (mounted) {
          setState(() => _error = 'Nie udało się zwolnić mikrofonu.');
        }
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
  }

  void _noteDown(int note) {
    if (!_recording ||
        _mode != TrainingInputMode.keyboard ||
        !_heldKeys.add(note)) {
      return;
    }
    final playable = _output.noteOn(note);
    _recorder.noteOn(note, _keyboardClock.elapsed);
    setState(() {
      _stableNote = note;
      if (!playable) {
        _error = 'Nie można odtworzyć klawiszy przez głośniki.';
      }
    });
  }

  void _noteUp(int note) {
    if (!_heldKeys.remove(note)) return;
    _output.noteOff(note);
    _recorder.noteOff(note, _keyboardClock.elapsed);
    if (mounted) {
      setState(() => _stableNote = _heldKeys.isEmpty ? null : _heldKeys.last);
    }
  }

  void _save() {
    if (_recording || _busy || _recorder.notes.isEmpty) return;
    try {
      final bytes = const MidiRecordingWriter().write(_recorder.notes);
      final name = 'learn-piano-${DateTime.now().millisecondsSinceEpoch}.mid';
      final ok = _exporter.save(bytes, name);
      setState(() {
        _error = ok ? null : 'Nie udało się pobrać pliku MIDI.';
        _message = ok ? 'Rozpoczęto pobieranie pliku MIDI.' : null;
      });
    } catch (_) {
      setState(() => _error = 'Nie udało się przygotować pliku MIDI.');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _startRequestId++;
    _keyboardClock.stop();
    _output.stopAll();
    _output.dispose();
    unawaited(_frames?.cancel());
    unawaited(_statuses?.cancel());
    unawaited(_input.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final notes = _recorder.notes;
    return Scaffold(
      appBar: AppBar(title: const Text('Nagrywanie nut')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Nagrywaj nuty, a nie dźwięk. Plik MIDI zapisuje wysokość, '
                    'początek i długość każdej nuty lokalnie w przeglądarce.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<TrainingInputMode>(
                    key: const Key('recording-input-mode'),
                    segments: const [
                      ButtonSegment(
                        value: TrainingInputMode.microphone,
                        label: Text('Pianino przez mikrofon'),
                        icon: Icon(Icons.mic),
                      ),
                      ButtonSegment(
                        value: TrainingInputMode.keyboard,
                        label: Text('Klawiatura ekranowa'),
                        icon: Icon(Icons.piano),
                      ),
                    ],
                    selected: {_mode},
                    onSelectionChanged: _recording || _busy
                        ? null
                        : (modes) => setState(() {
                            _mode = modes.first;
                            _error = null;
                          }),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        key: Key(
                          _recording ? 'recording-stop' : 'recording-start',
                        ),
                        onPressed: _busy
                            ? null
                            : _recording
                            ? _stop
                            : _start,
                        icon: Icon(
                          _recording ? Icons.stop : Icons.fiber_manual_record,
                        ),
                        label: Text(
                          _recording ? 'Zatrzymaj' : 'Rozpocznij nagrywanie',
                        ),
                      ),
                      OutlinedButton.icon(
                        key: const Key('recording-save'),
                        onPressed: _busy || _recording || notes.isEmpty
                            ? null
                            : _save,
                        icon: const Icon(Icons.download),
                        label: const Text('Zapisz MIDI'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _recording
                        ? 'Nagrywanie trwa • nuty: ${_recorder.noteCount}'
                        : 'Zarejestrowane nuty: ${notes.length}',
                    key: const Key('recording-note-count'),
                    style: theme.textTheme.titleMedium,
                  ),
                  if (_recorder.isFull)
                    const Text(
                      'Limit nut osiągnięty. Zakończ i zapisz nagranie.',
                    ),
                  if (_message != null)
                    Text(_message!, key: const Key('recording-message')),
                  if (_error != null)
                    Text(
                      _error!,
                      key: const Key('recording-error'),
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  const SizedBox(height: 12),
                  if (_mode == TrainingInputMode.keyboard) ...[
                    const Text(
                      'Naciskaj klawisze poniżej. Możesz grać kilka nut naraz.',
                    ),
                    const SizedBox(height: 8),
                    RecordingKeyboard(
                      range: _range,
                      enabled: _recording,
                      onNoteDown: _noteDown,
                      onNoteUp: _noteUp,
                    ),
                  ] else ...[
                    Text(
                      'Wykryta nuta: ${_stableNote == null ? '—' : PitchEstimate.nameForMidi(_stableNote!)}',
                      key: const Key('recording-detected-note'),
                      style: theme.textTheme.titleLarge,
                    ),
                    const Text(
                      'Mikrofon rozpoznaje pojedyncze nuty. '
                      'Wybrzmiewanie i szum mogą wpływać na ich długość.',
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    'Ostatnie zapisane nuty',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  if (notes.isEmpty)
                    const Text(
                      'Brak nut. Rozpocznij nagrywanie i zagraj melodię.',
                    )
                  else
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final note in notes.skip(
                          notes.length > 12 ? notes.length - 12 : 0,
                        ))
                          Chip(
                            label: Text(
                              '${PitchEstimate.nameForMidi(note.midiNote)} '
                              '${note.duration.inMilliseconds} ms',
                            ),
                          ),
                      ],
                    ),
                  const SizedBox(height: 8),
                  const Text(
                    'Nowe nagrywanie zastępuje poprzednie. '
                    'Zapisz MIDI przed rozpoczęciem kolejnego.',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _audioError(AudioInputFailure failure) => switch (failure) {
  AudioInputFailure.permissionDenied => 'Brak zgody na mikrofon.',
  AudioInputFailure.noDevice => 'Nie znaleziono mikrofonu.',
  AudioInputFailure.deviceBusy => 'Mikrofon jest zajęty.',
  AudioInputFailure.insecureContext => 'Mikrofon wymaga HTTPS lub localhost.',
  AudioInputFailure.unsupported => 'Przeglądarka nie obsługuje Web Audio.',
  AudioInputFailure.alreadyRunning => 'Mikrofon jest już włączony.',
  AudioInputFailure.cancelled => 'Uruchamianie mikrofonu anulowano.',
  AudioInputFailure.unknown => 'Nie udało się uruchomić mikrofonu.',
};
