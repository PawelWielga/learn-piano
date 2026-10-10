import 'dart:async';

import 'package:flutter/material.dart';

import '../audio/audio_input.dart';
import '../audio/audio_input_factory.dart';
import '../audio/note_output.dart';
import '../audio/note_output_factory.dart';
import '../instrument/instrument_range.dart';
import '../layout/landscape_gate.dart';
import '../midi/melody_part_analyzer.dart';
import '../pitch/note_event_tracker.dart';
import '../pitch/pitch_detector.dart';
import '../training/training_input_mode.dart';
import '../training/wait_for_note_engine.dart';
import '../widgets/training_stage.dart';

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
    this.noteOutput,
  });

  final MelodySelection selection;
  final InstrumentRange instrumentRange;
  final String? songTitle;

  /// Injected by widget tests; production uses the Web Audio adapter.
  final AudioInput? audioInput;

  /// Injectable for tests; web playback is initialized on the first key press.
  final NoteOutput? noteOutput;

  @override
  State<TrainingScreen> createState() => _TrainingScreenState();
}

class _TrainingScreenState extends State<TrainingScreen> {
  late final AudioInput _input;
  late final NoteOutput _output;
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
        _releaseKeyboardNotes();
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
    if (!mounted ||
        _mode != TrainingInputMode.microphone ||
        !_listening ||
        _busy ||
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

  /// Translate actual key down/up events into the same Wait for Note engine
  /// used by microphone pitch tracking, without synthetic audio feedback.
  void _onKeyboardDown(int note) {
    if (_mode != TrainingInputMode.keyboard ||
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
    if (_busy || _landscapeBlocked || _mode == mode) return;
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
    _releaseKeyboardNotes();
    setState(() => _snapshot = _engine.pause());
    if (_listening) await _stopCapture();
  }

  Future<void> _reset() async {
    if (_busy) return;
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
    final phaseLabel = switch (phase) {
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
    final attemptLabel = switch (_snapshot.lastAttempt) {
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
          currentIndex: _snapshot.currentIndex,
          progress: _snapshot.progress,
          expectedNote: _snapshot.expectedMidiNote,
          detectedNote: _mode == TrainingInputMode.keyboard
              ? _keyboardNote
              : _stableNote,
          lastAttempt: _snapshot.lastAttempt,
          phaseLabel: phaseLabel,
          attemptLabel: attemptLabel,
          songTitle: widget.songTitle ?? widget.selection.part.displayName,
          listening: _listening,
          busy: _busy,
          inputMode: _mode,
          onInputModeChanged: _switchInputMode,
          onNoteDown: _onKeyboardDown,
          onNoteUp: _onKeyboardUp,
          error: _error ?? _snapshot.errorMessage,
          onBack: () => Navigator.of(context).pop(),
          onPrimary: _busy
              ? null
              : switch (phase) {
                  TrainingPhase.ready => () => _start(),
                  TrainingPhase.running => _pause,
                  TrainingPhase.paused => () => _start(resume: true),
                  _ => null,
                },
          onReset: _busy || phase == TrainingPhase.error ? null : _reset,
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
