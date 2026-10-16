import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../audio/audio_input.dart';
import '../audio/audio_input_factory.dart';
import '../pitch/note_event_tracker.dart';
import '../pitch/pitch_detector.dart';
import '../pitch/detection_preferences.dart';
import '../pitch/detection_preferences_store_factory.dart';
import '../instrument/instrument_range.dart';
import '../instrument/instrument_range_store.dart';
import '../instrument/instrument_range_store_factory.dart';
import '../widgets/piano_keyboard.dart';

class MicrophonePreviewScreen extends StatefulWidget {
  const MicrophonePreviewScreen({
    super.key,
    this.audioInput,
    this.rangeStore,
    this.detectionPreferences,
  });

  /// Allows widget tests to inject a fake rather than opening a real device.
  final AudioInput? audioInput;
  final InstrumentRangeStore? rangeStore;
  final DetectionPreferences? detectionPreferences;

  @override
  State<MicrophonePreviewScreen> createState() =>
      _MicrophonePreviewScreenState();
}

class _MicrophonePreviewScreenState extends State<MicrophonePreviewScreen> {
  late final AudioInput _input;
  InstrumentRange _instrumentRange = InstrumentRange.defaultRange;
  StreamSubscription<PcmFrame>? _frameSubscription;
  StreamSubscription<AudioInputStatus>? _statusSubscription;

  late final PitchDetector _detector;
  late final NoteEventTracker _tracker;
  PitchEstimate? _candidate;
  NoteDetectionUpdate? _noteStatus;
  NoteEvent? _lastNoteOn;
  int _noteOnCount = 0;
  Duration? _lastAnalyzedAt;

  bool _busy = false;
  bool _listening = false;
  int _startRequestId = 0;
  int? _sampleRate;
  int? _frameSize;
  double _level = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _input = widget.audioInput ?? createAudioInput();
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
    _loadInstrumentRange();
    _frameSubscription = _input.frames.listen(_onFrame);
    _statusSubscription = _input.statuses.listen((status) {
      if (!mounted) return;
      if (status == AudioInputStatus.interrupted) {
        setState(() {
          _listening = false;
          _level = 0;
          _candidate = null;
          _tracker.reset();
          _noteStatus = null;
          _lastAnalyzedAt = null;
          _error =
              'Nasłuch został przerwany (np. zmiana karty lub '
              'odłączenie mikrofonu). Możesz go włączyć ponownie.';
        });
      }
    });
  }

  Future<void> _loadInstrumentRange() async {
    try {
      final saved = await (widget.rangeStore ?? createInstrumentRangeStore())
          .load();
      if (mounted && saved != null) {
        setState(() => _instrumentRange = saved);
      }
    } catch (_) {
      // Unavailable browser storage does not prevent the microphone test.
    }
  }

  void _onFrame(PcmFrame frame) {
    if (!mounted || !_listening || frame.samples.isEmpty) return;

    // Worklet timestamps use AudioContext time. Throttle analysis to about
    // 8 FPS on a 48 kHz stream; UI and YIN must not run for each audio frame.
    final last = _lastAnalyzedAt;
    if (last != null &&
        frame.capturedAt >= last &&
        frame.capturedAt - last < const Duration(milliseconds: 120)) {
      return;
    }
    _lastAnalyzedAt = frame.capturedAt;

    var sum = 0.0;
    for (final sample in frame.samples) {
      sum += sample * sample;
    }
    final rms = math.sqrt(sum / frame.samples.length);
    final pitch = _detector.detect(frame.samples, frame.sampleRate);
    final update = _tracker.observe(pitch, frame.capturedAt);

    setState(() {
      _sampleRate = frame.sampleRate;
      _frameSize = frame.samples.length;
      _level = rms.isFinite ? rms.clamp(0.0, 1.0) : 0;
      _candidate = pitch;
      _noteStatus = update;
      for (final event in update.events) {
        if (event.type == NoteEventType.noteOn) {
          _lastNoteOn = event;
          _noteOnCount++;
        }
      }
    });
  }

  Future<void> _start() async {
    if (_busy || _listening) return;
    final requestId = ++_startRequestId;
    setState(() {
      _busy = true;
      _error = null;
      _sampleRate = null;
      _frameSize = null;
      _level = 0;
      _candidate = null;
      _tracker.reset();
      _noteStatus = null;
      _lastNoteOn = null;
      _noteOnCount = 0;
      _lastAnalyzedAt = null;
    });
    try {
      await _input.start();
      if (!mounted || requestId != _startRequestId) {
        await _input.stop();
        return;
      }
      setState(() => _listening = true);
    } on AudioInputException catch (error) {
      if (mounted && requestId == _startRequestId) {
        setState(() => _error = _errorText(error.failure));
      }
    } catch (_) {
      if (mounted && requestId == _startRequestId) {
        setState(
          () => _error =
              'Nie udało się uruchomić mikrofonu. '
              'Sprawdź uprawnienia i spróbuj ponownie.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _input.stop();
      if (mounted) {
        setState(() {
          _listening = false;
          _level = 0;
          _candidate = null;
          _tracker.reset();
          _noteStatus = null;
          _lastAnalyzedAt = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Nie udało się poprawnie zatrzymać '
              'mikrofonu. Spróbuj zamknąć tę kartę.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    unawaited(_frameSubscription?.cancel());
    unawaited(_statusSubscription?.cancel());
    // The JS adapter stops MediaStreamTracks and closes AudioContext.
    unawaited(_input.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pitch = _candidate;
    final stableNote = _noteStatus?.stableNote;
    final phase = _noteStatus?.phase ?? NoteDetectionPhase.silent;
    final phaseDescription = switch (phase) {
      NoteDetectionPhase.silent => 'Brak nuty',
      NoteDetectionPhase.candidate => 'Sprawdzanie kandydata',
      NoteDetectionPhase.stable => 'Nuta stabilna',
      NoteDetectionPhase.releasing => 'Oczekiwanie na wybrzmienie',
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Test mikrofonu')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    _listening ? Icons.mic : Icons.mic_none,
                    size: 72,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _listening ? 'Nasłuch aktywny' : 'Mikrofon nieaktywny',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Dźwięk jest analizowany wyłącznie w tej przeglądarce. '
                    'Nie zapisujemy ani nie wysyłamy nagrań. '
                    'Włącz mikrofon i zagraj pojedynczą nutę.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  FilledButton.icon(
                    key: const Key('microphone-toggle'),
                    onPressed: _busy ? null : (_listening ? _stop : _start),
                    icon: Icon(_listening ? Icons.stop : Icons.mic),
                    label: Text(
                      _busy
                          ? 'Trwa zmiana stanu…'
                          : _listening
                          ? 'Wyłącz mikrofon'
                          : 'Włącz mikrofon',
                    ),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 18),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _error!,
                        key: const Key('microphone-error'),
                        style: TextStyle(color: theme.colorScheme.error),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),
                  Text(
                    'Wykryta nuta (chwilowy kandydat)',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      !_listening ? '—' : pitch?.noteName ?? 'Brak pewnej nuty',
                      key: const Key('detected-note'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.displayMedium?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    pitch == null || !_listening
                        ? 'Cisza lub niejednoznaczny dźwięk'
                        : '${pitch.frequencyHz.toStringAsFixed(1)} Hz  •  '
                              'pewność ${(pitch.confidence * 100).toStringAsFixed(0)}%  •  '
                              '${pitch.centsFromNote >= 0 ? '+' : ''}'
                              '${pitch.centsFromNote.toStringAsFixed(0)} centów',
                    key: const Key('pitch-details'),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'To surowy pomiar. Poniżej widać nutę potwierdzoną '
                    'przez stabilizację i osobne zdarzenia uderzeń.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 28),
                  Text('Stabilna nuta', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      !_listening || stableNote == null
                          ? '—'
                          : PitchEstimate.nameForMidi(stableNote),
                      key: const Key('stable-note'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium,
                    ),
                  ),
                  Text(
                    'Stan: ${_listening ? phaseDescription : 'Nieaktywny'}',
                    key: const Key('note-phase'),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Zdarzenia NoteOn: $_noteOnCount',
                    key: const Key('note-on-count'),
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    _lastNoteOn == null
                        ? 'Ostatnie uderzenie: —'
                        : 'Ostatnie uderzenie: '
                              '${PitchEstimate.nameForMidi(_lastNoteOn!.midiNote)}',
                    key: const Key('last-note-on'),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Jedna utrzymana nuta daje jedno zdarzenie. '
                    'Ponowne zagranie tej samej nuty wymaga wyraźnej '
                    'przerwy w dźwięku.',
                    style: theme.textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Podgląd klawiatury',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  PianoKeyboard(
                    range: _instrumentRange,
                    detectedNote: _listening ? stableNote : null,
                  ),
                  const SizedBox(height: 32),
                  Text('Poziom wejścia', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: _listening ? _level : 0,
                    minHeight: 12,
                    semanticsLabel: 'Poziom sygnału mikrofonu',
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Próbkowanie: ${_sampleRate == null ? '—' : '${_sampleRate!} Hz'}',
                    key: const Key('sample-rate'),
                  ),
                  Text(
                    'Rozmiar ramki: ${_frameSize == null ? '—' : '${_frameSize!} próbek'}',
                    key: const Key('frame-size'),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Detekcja obejmuje pojedyncze nuty (około C2–F#6). '
                    'Akordy i hałas mogą dawać niepewne wyniki.',
                    style: theme.textTheme.bodySmall,
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

String _errorText(AudioInputFailure failure) {
  return switch (failure) {
    AudioInputFailure.permissionDenied =>
      'Brak zgody na mikrofon. Zezwól na dostęp w ustawieniach '
          'witryny/przeglądarki i spróbuj ponownie.',
    AudioInputFailure.noDevice =>
      'Nie znaleziono mikrofonu. Podłącz urządzenie i spróbuj ponownie.',
    AudioInputFailure.deviceBusy => 'Nie można odczytać mikrofonu. Sprawdź, czy inne aplikacje go nie blokują.',
    AudioInputFailure.insecureContext =>
      'Mikrofon wymaga połączenia HTTPS lub adresu localhost.',
    AudioInputFailure.unsupported =>
      'Ta przeglądarka nie obsługuje wymaganych funkcji Web Audio.',
    AudioInputFailure.alreadyRunning => 'Mikrofon jest już włączony.',
    AudioInputFailure.cancelled => 'Uruchamianie mikrofonu anulowano.',
    AudioInputFailure.unknown =>
      'Nie udało się uruchomić mikrofonu. Spróbuj ponownie.',
  };
}
