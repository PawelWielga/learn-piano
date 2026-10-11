import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../audio/audio_input.dart';
import '../audio/audio_input_factory.dart';
import '../audio/note_output.dart';
import '../audio/note_output_factory.dart';
import '../instrument/instrument_range.dart';
import '../layout/landscape_gate.dart';
import '../midi/melody_part_analyzer.dart';
import '../pitch/note_event_tracker.dart';
import '../pitch/polyphonic_note_tracker.dart';
import '../pitch/pitch_detector.dart';
import '../pitch/detection_preferences.dart';
import '../pitch/detection_preferences_store_factory.dart';
import '../training/training_input_mode.dart';
import '../training/wait_for_note_engine.dart';
import '../widgets/training_stage.dart';

/// Exercises selected MIDI notes and chords using acoustic or touch NoteOn events.
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
    this.noteOutput,
    this.detectionPreferences,
  });

  final MelodySelection selection;
  final InstrumentRange instrumentRange;
  final String? songTitle;

  /// Injected by widget tests; production uses the Web Audio adapter.
  final AudioInput? audioInput;

  /// Injectable for tests; web playback is initialized on the first key press.
  final NoteOutput? noteOutput;

  /// Injected by tests; otherwise loaded from browser preferences.
  final DetectionPreferences? detectionPreferences;

  @override
  State<TrainingScreen> createState() => _TrainingScreenState();
}

class _TrainingScreenState extends State<TrainingScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AudioInput _input;
  late final NoteOutput _output;
  late final WaitForNoteEngine _engine;
  late TrainingSnapshot _snapshot;
  late final AnimationController _autoClock;
  bool _autoPlaying = false;
  int _autoNextIndex = 0;
  int? _autoActiveIndex;
  final Set<int> _autoActiveIndices = <int>{};
  Duration? _autoPlayhead;

  late final PitchDetector _detector;
  late final NoteEventTracker _tracker;
  late final PolyphonicNoteTracker _polyTracker;
  late final double _minimumRms;
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
  int? _keyboardNote;
  final Set<int> _heldKeyboardNotes = <int>{};
  TrainingInputMode _mode = TrainingInputMode.microphone;
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
    _output = widget.noteOutput ?? createNoteOutput();
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
    _minimumRms = preferences.minimumRms;
    _polyTracker = PolyphonicNoteTracker(minimumRms: _minimumRms);
    _autoClock = AnimationController(vsync: this)
      ..addListener(_onAutoFrame)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && _autoPlaying) {
          _stopAuto();
        }
      });
    WidgetsBinding.instance.addObserver(this);
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
        _stopAuto();
        _releaseKeyboardNotes();
        if (_snapshot.phase == TrainingPhase.running) {
          setState(() => _snapshot = _engine.pause());
        }
        if (_listening) unawaited(_stopCapture());
      });
    }
    _landscapeBlocked = blocked;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _stopAuto();
  }

  /// Start on the first MIDI onset so the browser can unlock audio within the
  /// button gesture. Later events follow their original MIDI timestamps.
  void _toggleAuto() {
    if (_autoPlaying) {
      _stopAuto();
      return;
    }
    if (_busy ||
        _landscapeBlocked ||
        _snapshot.phase == TrainingPhase.error ||
        widget.selection.notes.isEmpty) {
      return;
    }
    _startRequestId++;
    _releaseKeyboardNotes();
    if (_listening) unawaited(_stopCapture());

    final notes = widget.selection.notes;
    if (!_output.noteOn(notes.first.midiNote)) {
      setState(() => _error = 'Nie można odtworzyć MIDI w tej przeglądarce.');
      return;
    }
    final end = notes.map((note) => note.start + note.duration)
        .reduce((a, b) => a > b ? a : b);
    final total = end - notes.first.start;
    _autoClock.duration = total > Duration.zero
        ? total
        : const Duration(milliseconds: 1);
    setState(() {
      _snapshot = _engine.pause();
      _autoPlaying = true;
      _autoNextIndex = 1;
      _autoActiveIndex = 0;
      _autoActiveIndices..clear()..add(0);
      _autoPlayhead = notes.first.start;
      _error = null;
    });
    _autoClock.forward(from: 0);
  }

  void _onAutoFrame() {
    if (!mounted || !_autoPlaying) return;
    final notes = widget.selection.notes;
    final duration = _autoClock.duration!;
    final playhead =
        notes.first.start +
        Duration(
          microseconds: (duration.inMicroseconds * _autoClock.value).round(),
        );

    // Release each MIDI voice independently. Chords and overlapping bass
    // must never cut each other off when another note starts.
    for (final index in _autoActiveIndices.toList()) {
      final note = notes[index];
      if (note.start + note.duration <= playhead) {
        _output.noteOff(note.midiNote);
        _autoActiveIndices.remove(index);
      }
    }
    while (_autoNextIndex < notes.length &&
        notes[_autoNextIndex].start <= playhead) {
      final index = _autoNextIndex++;
      final next = notes[index];
      if (!_output.noteOn(next.midiNote)) {
        _stopAuto();
        if (mounted) {
          setState(() => _error = 'Odtwarzanie MIDI zostało przerwane.');
        }
        return;
      }
      _autoActiveIndices.add(index);
      if (next.duration == Duration.zero ||
          next.start + next.duration <= playhead) {
        _output.noteOff(next.midiNote);
        _autoActiveIndices.remove(index);
      }
    }
    _autoActiveIndex = _autoActiveIndices.isEmpty
        ? null
        : _autoActiveIndices.first;
    setState(() => _autoPlayhead = playhead);
  }

  void _stopAuto() {
    if (!_autoPlaying) return;
    _autoPlaying = false;
    _autoClock.stop();
    _output.stopAll();
    if (mounted) {
      setState(() {
        _autoActiveIndex = null;
        _autoActiveIndices.clear();
        _autoNextIndex = 0;
        _autoPlayhead = null;
      });
    }
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
      _polyTracker.reset();
      _snapshot = _engine.pause();
      _error =
          'Mikrofon został przerwany. Wznów ćwiczenie, '
          'gdy urządzenie będzie dostępne.';
    });
    // Also release tracks when the adapter only reported an interruption.
    unawaited(_input.stop().catchError((Object _) {}));
  }

  void _onFrame(PcmFrame frame) {
    if (!mounted ||
        _mode != TrainingInputMode.microphone ||
        !_listening ||
        _busy ||
        _autoPlaying ||
        frame.samples.isEmpty) {
      return;
    }

    final previous = _lastAnalyzedAt;
    if (previous != null &&
        frame.capturedAt >= previous &&
        frame.capturedAt - previous < const Duration(milliseconds: 120)) {
      return;
    }
    _lastAnalyzedAt = frame.capturedAt;

    final polyphonic = !widget.selection.part.isMonophonic;
    final pitch = polyphonic
        ? null
        : _detector.detect(frame.samples, frame.sampleRate);
    final detected = polyphonic
        ? null
        : _tracker.observe(pitch, frame.capturedAt);
    final events = polyphonic
        ? _polyTracker.observe(
            frame.samples,
            frame.sampleRate,
            frame.capturedAt,
          )
        : detected!.events;
    var energy = 0.0;
    for (final value in frame.samples) {
      energy += value * value;
    }
    final quiet = math.sqrt(energy / frame.samples.length) < _minimumRms;

    if (_awaitingSilence) {
      if (polyphonic
          ? quiet && _polyTracker.activeNotes.isEmpty
          : pitch == null &&
              detected!.stableNote == null &&
              detected.candidateNote == null) {
        _quietSince ??= frame.capturedAt;
        if (frame.capturedAt - _quietSince! >=
            const Duration(milliseconds: 240)) {
          _awaitingSilence = false;
          _engine.releaseHeldNotesAfterSilence();
          if (polyphonic) _polyTracker.reset();
        }
      } else {
        _quietSince = null;
      }
    }

    for (final event in events) {
      if (!_awaitingSilence) {
        _engine.onNoteEvent(event);
      }
    }

    final updated = _engine.snapshot;
    setState(() {
      _stableNote = polyphonic
          ? (_polyTracker.activeNotes.isEmpty
              ? null
              : _polyTracker.activeNotes.first)
          : detected!.stableNote;
      _snapshot = updated;
    });
    if (updated.isCompleted) {
      unawaited(_stopCapture());
    }
  }

  /// Translate actual key down/up events into the same Wait for Note engine
  /// used by microphone pitch tracking, without synthetic audio feedback.
  void _onKeyboardDown(int note) {
    if (_mode != TrainingInputMode.keyboard ||
        _autoPlaying ||
        _landscapeBlocked ||
        _busy ||
        _snapshot.isCompleted ||
        _snapshot.phase == TrainingPhase.error ||
        !_heldKeyboardNotes.add(note)) {
      return;
    }
    final audible = _output.noteOn(note);
    _engine.onNoteEvent(
      NoteEvent(type: NoteEventType.noteOn, midiNote: note, at: Duration.zero),
    );
    setState(() {
      _keyboardNote = note;
      _snapshot = _engine.snapshot;
      if (!audible) {
        _error =
            'Przeglądarka nie może odtworzyć dźwięku. '
            'Sprawdź ustawienia audio i spróbuj ponownie.';
      } else {
        _error = null;
      }
    });
  }

  void _onKeyboardUp(int note) {
    if (!_heldKeyboardNotes.remove(note)) return;
    _output.noteOff(note);
    _engine.onNoteEvent(
      NoteEvent(type: NoteEventType.noteOff, midiNote: note, at: Duration.zero),
    );
    if (mounted) {
      setState(() {
        _keyboardNote = _heldKeyboardNotes.isEmpty
            ? null
            : _heldKeyboardNotes.last;
      });
    }
  }

  /// Stop all synthesizer voices and release the engine's held-key gate.
  /// Called before changing mode, pausing, resetting or leaving the screen.
  void _releaseKeyboardNotes() {
    for (final note in _heldKeyboardNotes) {
      _engine.onNoteEvent(
        NoteEvent(
          type: NoteEventType.noteOff,
          midiNote: note,
          at: Duration.zero,
        ),
      );
    }
    _heldKeyboardNotes.clear();
    _keyboardNote = null;
    _output.stopAll();
  }

  Future<void> _switchInputMode(TrainingInputMode mode) async {
    if (_busy || _autoPlaying || _landscapeBlocked || _mode == mode) return;
    _startRequestId++;
    _releaseKeyboardNotes();
    if (_mode == TrainingInputMode.microphone) {
      // Cross-source held notes are not real key presses on the new source.
      _engine.releaseHeldNotesAfterSilence();
    }
    setState(() {
      _snapshot = _engine.pause();
      _mode = mode;
      _stableNote = null;
      _error = null;
    });
    if (_listening) await _stopCapture();
  }

  Future<void> _start({bool resume = false}) async {
    if (_busy ||
        _autoPlaying ||
        _listening ||
        _landscapeBlocked ||
        _snapshot.phase == TrainingPhase.error) {
      return;
    }
    if (_mode == TrainingInputMode.keyboard) {
      setState(() {
        _snapshot = resume ? _engine.resume() : _engine.start();
        _error = null;
      });
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
      _polyTracker.reset();
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
      _polyTracker.reset();
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
    if (_busy || _autoPlaying || _snapshot.phase != TrainingPhase.running) {
      return;
    }
    _releaseKeyboardNotes();
    setState(() => _snapshot = _engine.pause());
    if (_listening) await _stopCapture();
  }

  Future<void> _reset() async {
    if (_busy || _autoPlaying) return;
    _releaseKeyboardNotes();
    setState(() {
      _snapshot = _engine.reset();
      _error = null;
      _stableNote = null;
    });
    if (_listening) await _stopCapture();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoPlaying = false;
    _autoClock.dispose();
    _releaseKeyboardNotes();
    _output.dispose();
    unawaited(_frames?.cancel());
    unawaited(_statuses?.cancel());
    // dispose() stops MediaStreamTracks and closes the AudioContext.
    unawaited(_input.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final phase = _snapshot.phase;
    final phaseLabel = _autoPlaying
        ? 'Odsłuch wybranej partii MIDI'
        : switch (phase) {
            TrainingPhase.ready => 'Gotowe do ćwiczenia',
            TrainingPhase.running =>
              _mode == TrainingInputMode.keyboard
                  ? 'Graj na klawiaturze ekranowej'
                  : _awaitingSilence
                  ? 'Poczekaj na ciszę i zagraj pierwszą nutę'
                  : 'Słucham Twojego pianinka',
            TrainingPhase.paused => 'Ćwiczenie wstrzymane',
            TrainingPhase.completed => 'Brawo! Melodia ukończona',
            TrainingPhase.error => 'Nie można rozpocząć treningu',
          };
    final attemptLabel = _snapshot.matchedMidiNotes.isNotEmpty
        ? 'Trzymaj wszystkie nuty akordu jednocześnie.'
        : switch (_snapshot.lastAttempt) {
      TrainingAttempt.ignored => 'Zagraj wskazaną nutę.',
      TrainingAttempt.correct => 'Dobrze! Przejdź do kolejnej nuty.',
      TrainingAttempt.incorrect => 'Inna nuta. Spróbuj ponownie.',
    };

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: TrainingStage(
          notes: widget.selection.notes,
          range: widget.instrumentRange,
          phase: phase,
          currentIndex: _autoPlaying
              ? math.max(0, _autoNextIndex - 1)
              : _snapshot.currentIndex,
          progress: _autoPlaying ? _autoClock.value : _snapshot.progress,
          expectedNote: _autoPlaying
              ? _autoActiveIndex == null
                    ? null
                    : widget.selection.notes[_autoActiveIndex!].midiNote
              : _snapshot.expectedMidiNote,
          expectedNotes: _autoPlaying
              ? _autoActiveIndices.map((i) => widget.selection.notes[i].midiNote).toSet()
              : _snapshot.expectedMidiNotes,
          detectedNotes: _autoPlaying
              ? const <int>{}
              : _mode == TrainingInputMode.keyboard
                  ? _heldKeyboardNotes
                  : widget.selection.part.isMonophonic
                      ? <int>{if (_stableNote != null) _stableNote!}
                      : _polyTracker.activeNotes,
          detectedNote: _autoPlaying
              ? null
              : _mode == TrainingInputMode.keyboard
              ? _keyboardNote
              : _stableNote,
          lastAttempt: _autoPlaying
              ? TrainingAttempt.ignored
              : _snapshot.lastAttempt,
          phaseLabel: phaseLabel,
          attemptLabel: _autoPlaying
              ? 'Odtwarzanie MIDI bez oceniania Twojej gry.'
              : attemptLabel,
          songTitle: widget.songTitle ?? widget.selection.part.displayName,
          listening: _listening,
          busy: _busy,
          inputMode: _mode,
          autoPlaying: _autoPlaying,
          playhead: _autoPlayhead,
          onAutoPlay: _toggleAuto,
          onInputModeChanged: _switchInputMode,
          onNoteDown: _onKeyboardDown,
          onNoteUp: _onKeyboardUp,
          error: _error ?? _snapshot.errorMessage,
          onBack: () => Navigator.of(context).pop(),
          onPrimary: _busy || _autoPlaying
              ? null
              : switch (phase) {
                  TrainingPhase.ready => () => _start(),
                  TrainingPhase.running => _pause,
                  TrainingPhase.paused => () => _start(resume: true),
                  _ => null,
                },
          onReset: _busy || _autoPlaying || phase == TrainingPhase.error
              ? null
              : _reset,
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
