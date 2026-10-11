import '../instrument/instrument_range.dart';
import '../midi/melody_part_analyzer.dart';
import '../midi/midi_parser.dart';
import '../pitch/note_event_tracker.dart';

/// The training cursor is controlled by validated NoteOn events, never a timer.
enum TrainingPhase { ready, running, paused, completed, error }

/// Feedback produced by one incoming event.
enum TrainingAttempt { ignored, correct, incorrect }

/// Immutable state suitable for both a piano roll and a progress indicator.
class TrainingSnapshot {
  const TrainingSnapshot({
    required this.phase,
    required this.currentIndex,
    required this.totalNotes,
    required this.expectedMidiNote,
    this.expectedMidiNotes = const <int>{},
    this.matchedMidiNotes = const <int>{},
    required this.lastPlayedMidiNote,
    required this.lastAttempt,
    required this.errorMessage,
  });

  final TrainingPhase phase;

  /// Index of the next expected note. Equals [totalNotes] after completion.
  final int currentIndex;
  final int totalNotes;
  final int? expectedMidiNote;
  /// All pitches in the current onset group (chord).
  final Set<int> expectedMidiNotes;
  /// Chord pitches currently held, awaiting the other keys.
  final Set<int> matchedMidiNotes;
  final int? lastPlayedMidiNote;
  final TrainingAttempt lastAttempt;
  final String? errorMessage;

  int get completedNotes => currentIndex;
  bool get isCompleted => phase == TrainingPhase.completed;
  double get progress => totalNotes == 0 ? 0 : currentIndex / totalNotes;
}

/// State plus the result of processing a single acoustic note event.
class TrainingEventUpdate {
  const TrainingEventUpdate({required this.snapshot, required this.attempt});

  final TrainingSnapshot snapshot;
  final TrainingAttempt attempt;
}

/// Pure-Dart Wait for Note state machine. Does not own the microphone or clock.
///
/// Pass only events emitted by [NoteEventTracker], not raw pitch candidates.
/// The pressed-note set is tracked even while ready/paused, so an already
/// sounding note cannot score when start/resume/reset is pressed. NoteOff
/// releases this gate without advancing the melody.
///
/// The caller must feed the whole event stream in order (including NoteOff).
/// If a microphone session is interrupted, the UI integration (#14) must
/// stop capture and explicitly clear the detector/tracker before resuming.
class WaitForNoteEngine {
  WaitForNoteEngine(
    MelodySelection selection, {
    required InstrumentRange instrumentRange,
  }) : _notes = List<MidiNote>.unmodifiable(selection.notes) {
    if (!selection.part.canPractice || _notes.isEmpty) {
      _fail('Wybierz niepustą partię bez perkusji.');
    } else if (!_isOrderedAndValid(_notes)) {
      _fail('Melodia zawiera niepoprawne lub nieuporządkowane nuty.');
    } else if (!instrumentRange
        .checkNotes(_notes.map((note) => note.midiNote))
        .canPractice) {
      _fail('Melodia zawiera nuty poza zakresem Twojej klawiatury.');
    }
  }

  final List<MidiNote> _notes;
  final Set<int> _pressedNotes = <int>{};
  final Set<int> _chordHits = <int>{};
  // Near-simultaneous MP3 transcription onsets may differ by one/two hops.
  static const chordOnsetTolerance = Duration(milliseconds: 65);

  int get _groupEnd {
    if (_index >= _notes.length) return _index;
    final onset = _notes[_index].start;
    var end = _index + 1;
    while (end < _notes.length &&
        _notes[end].start - onset <= chordOnsetTolerance) {
      end++;
    }
    return end;
  }

  Set<int> get _expectedNotes => _index == _notes.length
      ? <int>{}
      : _notes.sublist(_index, _groupEnd).map((n) => n.midiNote).toSet();
  TrainingPhase _phase = TrainingPhase.ready;
  int _index = 0;
  int? _lastPlayedMidiNote;
  TrainingAttempt _lastAttempt = TrainingAttempt.ignored;
  String? _errorMessage;

  TrainingSnapshot get snapshot => TrainingSnapshot(
    phase: _phase,
    currentIndex: _index,
    totalNotes: _notes.length,
    expectedMidiNote: _index < _notes.length ? _notes[_index].midiNote : null,
    expectedMidiNotes: Set<int>.unmodifiable(_expectedNotes),
    matchedMidiNotes: Set<int>.unmodifiable(_chordHits),
    lastPlayedMidiNote: _lastPlayedMidiNote,
    lastAttempt: _lastAttempt,
    errorMessage: _errorMessage,
  );

  /// A paused or completed practice cannot be started again without reset.
  TrainingSnapshot start() {
    if (_phase == TrainingPhase.ready) {
      _phase = TrainingPhase.running;
    }
    return snapshot;
  }

  TrainingSnapshot pause() {
    if (_phase == TrainingPhase.running) {
      _phase = TrainingPhase.paused;
    }
    return snapshot;
  }

  TrainingSnapshot resume() {
    if (_phase == TrainingPhase.paused) {
      _phase = TrainingPhase.running;
    }
    return snapshot;
  }

  /// Restart progress but preserve currently sounding keys for safety.
  ///
  /// A new NoteOff/NoteOn pair is required before a previously held pitch
  /// can count again. Caller must also reset the pitch tracker when starting
  /// an entirely new *microphone* capture session.
  TrainingSnapshot reset() {
    if (_phase != TrainingPhase.error) {
      _index = 0;
      _chordHits.clear();
      _phase = TrainingPhase.ready;
      _lastPlayedMidiNote = null;
      _lastAttempt = TrainingAttempt.ignored;
    }
    return snapshot;
  }

  /// Clears remembered held pitches only after the input adapter has observed
  /// a continuous quiet period following a new capture session.
  ///
  /// Do not call this on pause or reset: those operations alone do not prove
  /// that a physical key was released.
  void releaseHeldNotesAfterSilence() {
    _pressedNotes.clear();
    _chordHits.clear();
  }

  TrainingEventUpdate onNoteEvent(NoteEvent event) {
    if (event.midiNote < 0 || event.midiNote > 127) {
      return TrainingEventUpdate(
        snapshot: snapshot,
        attempt: TrainingAttempt.ignored,
      );
    }

    if (event.type == NoteEventType.noteOff) {
      _pressedNotes.remove(event.midiNote);
      // A chord needs all keys held together, not one after another.
      _chordHits.remove(event.midiNote);
      return TrainingEventUpdate(
        snapshot: snapshot,
        attempt: TrainingAttempt.ignored,
      );
    }

    // Duplicate NoteOn from the same held key is not another key press.
    // This also protects consecutive equal notes when downstream events
    // are duplicated or arrive while paused.
    if (!_pressedNotes.add(event.midiNote) || _phase != TrainingPhase.running) {
      return TrainingEventUpdate(
        snapshot: snapshot,
        attempt: TrainingAttempt.ignored,
      );
    }

    _lastPlayedMidiNote = event.midiNote;
    final expected = _expectedNotes;
    if (!expected.contains(event.midiNote)) {
      _lastAttempt = TrainingAttempt.incorrect;
      return TrainingEventUpdate(
        snapshot: snapshot,
        attempt: TrainingAttempt.incorrect,
      );
    }

    _chordHits.add(event.midiNote);
    if (!_chordHits.containsAll(expected)) {
      _lastAttempt = TrainingAttempt.ignored;
      return TrainingEventUpdate(
        snapshot: snapshot,
        attempt: TrainingAttempt.ignored,
      );
    }
    _index = _groupEnd;
    _chordHits.clear();
    _lastAttempt = TrainingAttempt.correct;
    if (_index == _notes.length) {
      _phase = TrainingPhase.completed;
    }
    return TrainingEventUpdate(
      snapshot: snapshot,
      attempt: TrainingAttempt.correct,
    );
  }

  void _fail(String message) {
    _phase = TrainingPhase.error;
    _errorMessage = message;
  }

  static bool _isOrderedAndValid(List<MidiNote> notes) {
    MidiNote? previous;
    for (final note in notes) {
      if (note.midiNote < 0 ||
          note.midiNote > 127 ||
          note.startTick < 0 ||
          note.endTick < note.startTick ||
          note.duration.isNegative) {
        return false;
      }
      if (previous != null && note.startTick < previous.startTick) {
        return false;
      }
      previous = note;
    }
    return true;
  }
}
