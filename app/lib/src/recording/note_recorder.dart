/// One key press in a local recording. Times are relative to recording start.
class RecordedNote {
  const RecordedNote({
    required this.midiNote,
    required this.start,
    required this.duration,
    this.velocity = 96,
  });

  final int midiNote;
  final Duration start;
  final Duration duration;
  final int velocity;
}

/// Collects NoteOn/NoteOff pairs without retaining PCM or using browser APIs.
class NoteRecorder {
  NoteRecorder({this.maxNotes = 8192}) : assert(maxNotes > 0);

  final int maxNotes;
  final List<RecordedNote> _notes = [];
  final Map<int, _ActiveNote> _active = {};
  Duration _lastAt = Duration.zero;
  bool _recording = false;

  bool get isRecording => _recording;
  bool get isFull => _notes.length + _active.length >= maxNotes;
  int get noteCount => _notes.length + _active.length;
  int get activeCount => _active.length;

  List<RecordedNote> get notes {
    final sorted = List<RecordedNote>.of(_notes)
      ..sort((a, b) {
        final byStart = a.start.compareTo(b.start);
        return byStart != 0 ? byStart : a.midiNote.compareTo(b.midiNote);
      });
    return List.unmodifiable(sorted);
  }

  void start() {
    _notes.clear();
    _active.clear();
    _lastAt = Duration.zero;
    _recording = true;
  }

  void noteOn(int midiNote, Duration at, {int velocity = 96}) {
    if (!_recording || midiNote < 0 || midiNote > 127 ||
        velocity < 1 || velocity > 127) {
      return;
    }
    final time = _normalize(at);
    if (_active.containsKey(midiNote) || isFull) return;
    _active[midiNote] = _ActiveNote(time, velocity);
  }

  void noteOff(int midiNote, Duration at) {
    if (!_recording) return;
    final time = _normalize(at);
    final started = _active.remove(midiNote);
    if (started == null) return;
    _notes.add(RecordedNote(
      midiNote: midiNote,
      start: started.at,
      duration: time > started.at ? time - started.at : Duration.zero,
      velocity: started.velocity,
    ));
  }

  /// Complete held notes even when the user stops without releasing a key.
  void stop(Duration at) {
    if (!_recording) return;
    final time = _normalize(at);
    for (final note in _active.keys.toList()) {
      noteOff(note, time);
    }
    _recording = false;
  }

  Duration _normalize(Duration at) {
    if (at.isNegative || at < _lastAt) return _lastAt;
    _lastAt = at;
    return at;
  }
}

class _ActiveNote {
  const _ActiveNote(this.at, this.velocity);
  final Duration at;
  final int velocity;
}
