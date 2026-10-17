import '../audio/audio_file_picker.dart';
import '../pitch/detection_preferences.dart';
import '../recording/note_recorder.dart';

/// File transcription is separate from the microphone's realtime NoteOn stream.
enum TranscriptionMode { fast, accurate }

class TranscriptionOptions {
  const TranscriptionOptions({
    this.mode = TranscriptionMode.accurate,
    this.preferences = const DetectionPreferences(),
  });

  final TranscriptionMode mode;
  final DetectionPreferences preferences;
}

/// Position relative to a note onset. Values are in cents, not MIDI semitones.
class NotePitchBend {
  const NotePitchBend({required this.at, required this.cents});

  final Duration at;
  final double cents;
}

/// Platform-independent output shared by DSP and future offline ML adapters.
class TranscribedNote {
  const TranscribedNote({
    required this.midiNote,
    required this.start,
    required this.end,
    this.velocity = 96,
    this.confidence,
    this.pitchBends = const <NotePitchBend>[],
  });

  final int midiNote;
  final Duration start;
  final Duration end;
  final int velocity;

  /// Optional model-specific 0–1 confidence; null is not a claim of certainty.
  final double? confidence;
  final List<NotePitchBend> pitchBends;

  Duration get duration => end - start;

  RecordedNote toRecordedNote() => RecordedNote(
    midiNote: midiNote,
    start: start,
    duration: duration,
    velocity: velocity,
  );

  void validate(Duration audioDuration) {
    if (midiNote < 0 ||
        midiNote > 127 ||
        velocity < 1 ||
        velocity > 127 ||
        start.isNegative ||
        end <= start ||
        end > audioDuration ||
        (confidence != null &&
            (!confidence!.isFinite || confidence! < 0 || confidence! > 1))) {
      throw const FormatException('Silnik zwrócił niepoprawną nutę.');
    }
    for (final bend in pitchBends) {
      if (bend.at.isNegative ||
          bend.at > duration ||
          !bend.cents.isFinite ||
          bend.cents.abs() > 2400) {
        throw const FormatException('Silnik zwrócił niepoprawne odstrojenie.');
      }
    }
  }
}

class TranscriptionResult {
  const TranscriptionResult({
    required this.engineId,
    required this.duration,
    required this.notes,
    this.truncated = false,
    this.limitations = const <String>[],
  });

  final String engineId;
  final Duration duration;
  final List<TranscribedNote> notes;
  final bool truncated;

  /// Human-readable, honest limitations of the engine/particular result.
  final List<String> limitations;

  bool get hasPitchBends => notes.any((note) => note.pitchBends.isNotEmpty);

  /// Validate untrusted model output before MIDI writing. Do not silently
  /// clamp invalid pitches/times or destroy deliberately overlapping chords.
  List<RecordedNote> toRecordedNotes() {
    if (engineId.trim().isEmpty || duration.isNegative || notes.length > 8192) {
      throw const FormatException('Silnik zwrócił niepoprawny wynik.');
    }
    final normalized = <RecordedNote>[];
    for (final note in notes) {
      note.validate(duration);
      normalized.add(note.toRecordedNote());
    }
    normalized.sort((a, b) {
      final byTime = a.start.compareTo(b.start);
      return byTime != 0 ? byTime : a.midiNote.compareTo(b.midiNote);
    });
    return List<RecordedNote>.unmodifiable(normalized);
  }
}

/// Implementations process only local decoded PCM. The caller owns cancellation
/// and must ignore callbacks/results after a request is superseded or disposed.
/// Engines should check [isCancelled] at bounded checkpoints and throw
/// [TranscriptionCancelled]; progress is a fraction in [0, 1].
abstract interface class TranscriptionEngine {
  String get engineId;

  Future<TranscriptionResult> transcribe(
    DecodedAudioFile audio, {
    TranscriptionOptions options = const TranscriptionOptions(),
    bool Function()? isCancelled,
    void Function(double)? onProgress,
  });
}

class TranscriptionCancelled implements Exception {
  const TranscriptionCancelled();
}
