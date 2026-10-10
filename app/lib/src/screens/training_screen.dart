import 'dart:async';

import 'package:flutter/material.dart';

import '../audio/audio_input.dart';
import '../audio/audio_input_factory.dart';
import '../instrument/instrument_range.dart';
import '../layout/landscape_gate.dart';
import '../midi/melody_part_analyzer.dart';
import '../pitch/note_event_tracker.dart';
import '../pitch/pitch_detector.dart';
import '../training/wait_for_note_engine.dart';
import '../widgets/falling_notes_view.dart';
import '../widgets/piano_keyboard.dart';

/// Exercises one validated monophonic MIDI part against acoustic NoteOn events.
///
/// The imported file and captured PCM stay in the browser. A new microphone
/// session must first observe silence so a ringing/held key cannot score as
/// a fresh strike when starting or resuming after an interruption.
class TrainingScreen extends StatefulWidget {
  const TrainingScreen({
    super.key,
    required this.selection,
    required this.instrumentRange,
    this.songTitle,
    this.audioInput,
  });

  final MelodySelection selection;
  final InstrumentRange instrumentRange;
  final String? songTitle;

  /// Injected by widget tests; production uses the Web Audio adapter.
  final AudioInput? audioInput;

  @override
  State<TrainingScreen> createState() => _TrainingScreenState();
}

class _TrainingScreenState extends State<TrainingScreen> {
  late final AudioInput _input;
  late final WaitForNoteEngine _engine;
  late TrainingSnapshot _snapshot;

  final PitchDetector _detector = const PitchDetector();
  final NoteEventTracker _tracker = NoteEventTracker();
  StreamSubscription<PcmFrame>? _frames;
  StreamSubscription<AudioInputStatus>? _statuses;

  bool _busy = false;
  bool _listening = false;
  bool _landscapeBlocked = false;
  int _startRequestId = 0;
  bool _awaitingSilence = true;
  Duration? _quietSince;
  Duration? _lastAnalyzedAt;
  int? _stableNote;
  String? _error;

  @override
  void initState() {
    super.initState();
    _engine = WaitForNoteEngine(
      widget.selection,
      instrumentRange: widget.instrumentRange,
    );
    _snapshot = _engine.snapshot;
    _input = widget.audioInput ?? createAudioInput();
    _frames = _input.frames.listen(_onFrame);
    _statuses = _input.statuses.listen(_onAudioStatus);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final blocked = isPortraitViewport(context);
    if (blocked && !_landscapeBlocked) {
      // Cancel a pending getUserMedia request as well as active capture.
      _startRequestId++;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_landscapeBlocked) return;
        if (_snapshot.phase == TrainingPhase.running) {
          setState(() => _snapshot = _engine.pause());
        }
        if (_listening) unawaited(_stopCapture());
      });
    }
    _landscapeBlocked = blocked;
  }

  void _onAudioStatus(AudioInputStatus status) {
    if (!mounted || !_listening || status == AudioInputStatus.listening) {
      return;
    }
    // An unexpected stream loss must never leave a running exercise accepting
    // stale events. Explicit stop() sets _listening=false before closing audio.
    setState(() {
      _listening = false;
      _stableNote = null;
      _lastAnalyzedAt = null;
      _quietSince = null;
      _awaitingSilence = true;
      _tracker.reset();
      _snapshot = _engine.pause();
      _error =
          'Mikrofon został przerwany. Wznów ćwiczenie, '
          'gdy urządzenie będzie dostępne.';
    });
    // Also release tracks when the adapter only reported an interruption.
    unawaited(_input.stop().catchError((Object _) {}));
  }

  void _onFrame(PcmFrame frame) {
    if (!mounted || !_listening || _busy || frame.samples.isEmpty) return;

    final previous = _lastAnalyzedAt;
    if (previous != null &&
        frame.capturedAt >= previous &&
        frame.capturedAt - previous < const Duration(milliseconds: 120)) {
      return;
    }
    _lastAnalyzedAt = frame.capturedAt;

    final pitch = _detector.detect(frame.samples, frame.sampleRate);
    final detected = _tracker.observe(pitch, frame.capturedAt);

    if (_awaitingSilence) {
      if (pitch == null &&
          detected.stableNote == null &&
          detected.candidateNote == null) {
        _quietSince ??= frame.capturedAt;
        if (frame.capturedAt - _quietSince! >=
            const Duration(milliseconds: 240)) {
          _awaitingSilence = false;
          // Only measured silence releases keys retained by the engine
          // from an earlier microphone session.
          _engine.releaseHeldNotesAfterSilence();
        }
      } else {
        _quietSince = null;
      }
    }

    for (final event in detected.events) {
      if (!_awaitingSilence) {
        _engine.onNoteEvent(event);
      }
    }

    final updated = _engine.snapshot;
    setState(() {
      _stableNote = detected.stableNote;
      _snapshot = updated;
    });
    if (updated.isCompleted) {
      unawaited(_stopCapture());
    }
  }

  Future<void> _start({bool resume = false}) async {
    if (_busy ||
        _listening ||
        _landscapeBlocked ||
        _snapshot.phase == TrainingPhase.error) {
      return;
    }
    final requestId = ++_startRequestId;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await _input.start();
      if (!mounted || requestId != _startRequestId || _landscapeBlocked) {
        await _input.stop();
        return;
      }
      _tracker.reset();
      _lastAnalyzedAt = null;
      _quietSince = null;
      setState(() {
        _snapshot = resume ? _engine.resume() : _engine.start();
        _listening = true;
        _awaitingSilence = true;
        _stableNote = null;
      });
    } on AudioInputException catch (exception) {
      if (mounted && requestId == _startRequestId) {
        setState(() => _error = _audioErrorText(exception.failure));
      }
    } catch (_) {
      if (mounted && requestId == _startRequestId) {
        setState(() => _error = 'Nie udało się uruchomić mikrofonu.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stopCapture() async {
    if (_busy) return;
    final wasListening = _listening;
    setState(() {
      _busy = true;
      _listening = false;
    });
    try {
      if (wasListening) await _input.stop();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Nie udało się zatrzymać mikrofonu. '
              'Zamknij kartę, jeśli urządzenie nadal nasłuchuje.',
        );
      }
    } finally {
      _tracker.reset();
      _lastAnalyzedAt = null;
      _quietSince = null;
      if (mounted) {
        setState(() {
          _stableNote = null;
          _awaitingSilence = true;
          _busy = false;
        });
      }
    }
  }

  Future<void> _pause() async {
    if (_busy || _snapshot.phase != TrainingPhase.running) return;
    setState(() => _snapshot = _engine.pause());
    await _stopCapture();
  }

  Future<void> _reset() async {
    if (_busy) return;
    setState(() {
      _snapshot = _engine.reset();
      _error = null;
    });
    await _stopCapture();
  }

  @override
  void dispose() {
    unawaited(_frames?.cancel());
    unawaited(_statuses?.cancel());
    // dispose() stops MediaStreamTracks and closes the AudioContext.
    unawaited(_input.dispose());
    super.dispose();
  }

  /// A short landscape viewport has no room for the desktop's long scroll.
  /// Keep progress, audio state, piano roll and actions on screen together.
  Widget _buildCompactScaffold(
    BuildContext context, {
    required TrainingPhase phase,
    required String phaseLabel,
    required String attemptLabel,
    required int? expected,
    required int? detected,
  }) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 44,
        title: Text('Trening', style: theme.textTheme.titleMedium),
        actions: [
          TextButton(
            key: const Key('training-change-song'),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Zmień utwór'),
          ),
        ],
      ),
      body: SafeArea(
        child: _buildCompactBody(
          context,
          phase: phase,
          phaseLabel: phaseLabel,
          attemptLabel: attemptLabel,
          expected: expected,
          detected: detected,
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  key: const Key('training-primary'),
                  onPressed: _busy
                      ? null
                      : switch (phase) {
                          TrainingPhase.ready => () => _start(),
                          TrainingPhase.running => _pause,
                          TrainingPhase.paused => () => _start(resume: true),
                          _ => null,
                        },
                  icon: Icon(
                    phase == TrainingPhase.running
                        ? Icons.pause
                        : Icons.play_arrow,
                  ),
                  label: Text(switch (phase) {
                    TrainingPhase.ready => 'Start i mikrofon',
                    TrainingPhase.running => 'Pauza',
                    TrainingPhase.paused => 'Wznów',
                    _ => 'Zakończono',
                  }),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('training-reset'),
                  onPressed: _busy || phase == TrainingPhase.error
                      ? null
                      : _reset,
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Reset'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompactBody(
    BuildContext context, {
    required TrainingPhase phase,
    required String phaseLabel,
    required String attemptLabel,
    required int? expected,
    required int? detected,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final microphoneLabel = _listening
        ? 'Mikrofon aktywny'
        : 'Mikrofon wyłączony';
    final compactPhaseLabel = phase == TrainingPhase.running && _awaitingSilence
        ? 'Czekam na ciszę'
        : phaseLabel;
    final feedbackLabel = switch (_snapshot.lastAttempt) {
      TrainingAttempt.ignored => null,
      TrainingAttempt.correct => 'Poprawnie',
      TrainingAttempt.incorrect => 'Błędna nuta',
    };

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        compactPhaseLabel,
                        key: const Key('training-phase'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    _listening ? Icons.mic : Icons.mic_off,
                    size: 16,
                    color: _listening
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    microphoneLabel,
                    key: const Key('training-microphone-status'),
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${_snapshot.completedNotes} / ${_snapshot.totalNotes} nut',
                    key: const Key('training-progress-label'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: Text(
                      'Oczekiwana: ${expected == null ? '—' : PitchEstimate.nameForMidi(expected)}',
                      key: const Key('training-expected'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: scheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: Text(
                      'Wykryta: ${detected == null ? '—' : PitchEstimate.nameForMidi(detected)}',
                      key: const Key('training-detected'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (feedbackLabel != null) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: Semantics(
                        liveRegion: true,
                        label: attemptLabel,
                        child: Text(
                          feedbackLabel,
                          key: const Key('training-feedback'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color:
                                _snapshot.lastAttempt ==
                                    TrainingAttempt.incorrect
                                ? scheme.error
                                : scheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 5),
              LinearProgressIndicator(
                key: const Key('training-progress'),
                value: _snapshot.progress,
                minHeight: 4,
                semanticsLabel: 'Postęp ćwiczenia',
              ),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                key: const Key('training-microphone-error'),
                style: TextStyle(color: scheme.error, fontSize: 12),
              ),
            ),
          ),
        Expanded(
          child: switch (phase) {
            TrainingPhase.completed => Center(
              child: Column(
                key: const Key('training-completed'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle, color: scheme.primary, size: 32),
                  const SizedBox(height: 4),
                  const Text('Ukończono wszystkie nuty!'),
                  const Text('Wybierz Reset, aby zagrać ponownie.'),
                ],
              ),
            ),
            TrainingPhase.error => Center(
              child: Text(
                _snapshot.errorMessage ?? 'Niepoprawna melodia.',
                style: TextStyle(color: scheme.error),
              ),
            ),
            _ => LayoutBuilder(
              builder: (context, constraints) {
                // Very short split-screen windows need a small vertical scroll.
                if (constraints.maxHeight < 125) {
                  return SingleChildScrollView(
                    child: FallingNotesView(
                      notes: widget.selection.notes,
                      range: widget.instrumentRange,
                      currentIndex: _snapshot.currentIndex,
                      detectedNote: detected,
                      compact: true,
                      rollHeight: 54,
                      keyboardHeight: 72,
                    ),
                  );
                }
                final keyboardHeight = (constraints.maxHeight * 0.60).clamp(
                  68.0,
                  154.0,
                );
                return FallingNotesView(
                  notes: widget.selection.notes,
                  range: widget.instrumentRange,
                  currentIndex: _snapshot.currentIndex,
                  detectedNote: detected,
                  compact: true,
                  rollHeight: constraints.maxHeight - keyboardHeight,
                  keyboardHeight: keyboardHeight,
                );
              },
            ),
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final phase = _snapshot.phase;
    final expected = _snapshot.expectedMidiNote;
    final detected = _stableNote;
    final theme = Theme.of(context);

    final phaseLabel = switch (phase) {
      TrainingPhase.ready => 'Gotowe do ćwiczenia',
      TrainingPhase.running =>
        _awaitingSilence
            ? 'Poczekaj na ciszę i zagraj pierwszą nutę'
            : 'Słucham Twojego pianinka',
      TrainingPhase.paused => 'Ćwiczenie wstrzymane',
      TrainingPhase.completed => 'Brawo! Melodia ukończona',
      TrainingPhase.error => 'Nie można rozpocząć treningu',
    };
    final attemptLabel = switch (_snapshot.lastAttempt) {
      TrainingAttempt.ignored => 'Zagraj wskazaną nutę.',
      TrainingAttempt.correct => 'Dobrze! Przejdź do kolejnej nuty.',
      TrainingAttempt.incorrect => 'Inna nuta. Spróbuj ponownie.',
    };
    final viewport = MediaQuery.sizeOf(context);
    if (viewport.width > viewport.height && viewport.height < 560) {
      return _buildCompactScaffold(
        context,
        phase: phase,
        phaseLabel: phaseLabel,
        attemptLabel: attemptLabel,
        expected: expected,
        detected: detected,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trening'),
        actions: [
          TextButton(
            key: const Key('training-change-song'),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Zmień utwór'),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              children: [
                Text(
                  widget.songTitle ?? widget.selection.part.displayName,
                  key: const Key('training-song-title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    phaseLabel,
                    key: const Key('training-phase'),
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  key: const Key('training-progress'),
                  value: _snapshot.progress,
                  minHeight: 8,
                  semanticsLabel: 'Postęp ćwiczenia',
                ),
                const SizedBox(height: 8),
                Text(
                  '${_snapshot.completedNotes} / ${_snapshot.totalNotes} nut',
                  key: const Key('training-progress-label'),
                ),
                Text(
                  _listening
                      ? 'Mikrofon aktywny. Dźwięk jest analizowany lokalnie.'
                      : 'Mikrofon wyłączony. Dźwięk nie jest wysyłany na serwer.',
                  key: const Key('training-microphone-status'),
                  style: theme.textTheme.bodySmall,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      key: const Key('training-microphone-error'),
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                if (phase == TrainingPhase.completed) ...[
                  Card(
                    key: const Key('training-completed'),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Icon(
                            Icons.check_circle,
                            size: 64,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Ukończono wszystkie nuty!',
                            style: theme.textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          const Text('Wybierz Reset, aby zagrać ponownie.'),
                        ],
                      ),
                    ),
                  ),
                ] else if (phase == TrainingPhase.error) ...[
                  Text(
                    _snapshot.errorMessage ?? 'Niepoprawna melodia.',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ] else ...[
                  Text(
                    'Oczekiwana: ${expected == null ? '—' : PitchEstimate.nameForMidi(expected)}',
                    key: const Key('training-expected'),
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Wykryta: ${detected == null ? '—' : PitchEstimate.nameForMidi(detected)}',
                    key: const Key('training-detected'),
                  ),
                  const SizedBox(height: 6),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      attemptLabel,
                      key: const Key('training-feedback'),
                      style: TextStyle(
                        color:
                            _snapshot.lastAttempt == TrainingAttempt.incorrect
                            ? theme.colorScheme.error
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FallingNotesView(
                    notes: widget.selection.notes,
                    range: widget.instrumentRange,
                    currentIndex: _snapshot.currentIndex,
                    detectedNote: detected,
                  ),
                ],
                const SizedBox(height: 12),
                if (phase == TrainingPhase.completed)
                  PianoKeyboard(
                    range: widget.instrumentRange,
                    showRangeLabel: false,
                  ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  key: const Key('training-primary'),
                  onPressed: _busy
                      ? null
                      : switch (phase) {
                          TrainingPhase.ready => () => _start(),
                          TrainingPhase.running => _pause,
                          TrainingPhase.paused => () => _start(resume: true),
                          _ => null,
                        },
                  icon: Icon(
                    phase == TrainingPhase.running
                        ? Icons.pause
                        : Icons.play_arrow,
                  ),
                  label: Text(switch (phase) {
                    TrainingPhase.ready => 'Start i mikrofon',
                    TrainingPhase.running => 'Pauza',
                    TrainingPhase.paused => 'Wznów',
                    _ => 'Zakończono',
                  }),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('training-reset'),
                  onPressed: _busy || phase == TrainingPhase.error
                      ? null
                      : _reset,
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Reset'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _audioErrorText(AudioInputFailure failure) => switch (failure) {
  AudioInputFailure.permissionDenied =>
    'Brak zgody na mikrofon. Zezwól na dostęp w ustawieniach witryny.',
  AudioInputFailure.noDevice => 'Nie znaleziono mikrofonu. Podłącz urządzenie.',
  AudioInputFailure.deviceBusy => 'Mikrofon jest zajęty przez inną aplikację.',
  AudioInputFailure.insecureContext => 'Mikrofon wymaga HTTPS lub localhost.',
  AudioInputFailure.unsupported =>
    'Przeglądarka nie obsługuje wymaganych funkcji Web Audio.',
  AudioInputFailure.alreadyRunning => 'Mikrofon jest już włączony.',
  AudioInputFailure.cancelled => 'Uruchamianie mikrofonu anulowano.',
  AudioInputFailure.unknown => 'Nie udało się uruchomić mikrofonu.',
};
