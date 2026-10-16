import '../audio/audio_input.dart';
import 'note_event_tracker.dart';
import 'pitch_detector.dart';
import 'polyphonic_note_tracker.dart';

/// A transport-neutral source of realtime NoteOn/NoteOff transitions.
///
/// Kept separate from file transcription. Both adapters accept the same PCM
/// packets that the Web Audio worklet emits; Android capture can supply them
/// without importing JS or Flutter.
abstract class RealtimeNoteDetector {
  RealtimeDetection observe(PcmFrame frame);
  void reset();
}

/// Source is explicit so scorecards never compare mono and chord results as
/// though they were produced by the same algorithm.
enum RealtimeDetectorSource { yin, legacyPolyphonicFft }

/// Evidence is NOT a calibrated posterior probability. In particular the
/// current FFT matcher cannot provide trustworthy per-note confidence.
enum RealtimeEvidence { periodicity, uncalibratedPolyphony }

class RealtimeDetection {
  const RealtimeDetection({
    required this.source,
    required this.events,
    required this.activeNotes,
    required this.evidence,
    this.candidateMidiNote,
    this.periodicityConfidence,
  });

  final RealtimeDetectorSource source;
  final List<NoteEvent> events;
  final Set<int> activeNotes;
  final RealtimeEvidence evidence;
  final int? candidateMidiNote;

  /// YIN's periodicity score only. Null for the experimental chord tracker;
  /// do not turn null into a made-up confidence or treat it as certainty.
  final double? periodicityConfidence;

  bool get hasCalibratedNoteProbabilities => false;
}

/// Reproduces the mono training screen's 120 ms detector cadence.
/// Adapter for benchmarking / migration; production screen is unchanged.
class YinRealtimeDetector implements RealtimeNoteDetector {
  YinRealtimeDetector({
    this.pitchDetector = const PitchDetector(),
    NoteEventTracker? noteTracker,
  }) : _tracker = noteTracker ?? NoteEventTracker();

  final PitchDetector pitchDetector;
  final NoteEventTracker _tracker;
  Duration? _lastAnalyzed;
  RealtimeDetection _last = const RealtimeDetection(
    source: RealtimeDetectorSource.yin,
    events: <NoteEvent>[],
    activeNotes: <int>{},
    evidence: RealtimeEvidence.periodicity,
  );

  @override
  RealtimeDetection observe(PcmFrame frame) {
    if (frame.samples.isEmpty || frame.sampleRate <= 0) {
      return _last;
    }
    if (_lastAnalyzed != null &&
        frame.capturedAt >= _lastAnalyzed! &&
        frame.capturedAt - _lastAnalyzed! < const Duration(milliseconds: 120)) {
      return RealtimeDetection(
        source: RealtimeDetectorSource.yin,
        events: const <NoteEvent>[],
        activeNotes: _last.activeNotes,
        evidence: RealtimeEvidence.periodicity,
        candidateMidiNote: _last.candidateMidiNote,
        periodicityConfidence: _last.periodicityConfidence,
      );
    }
    _lastAnalyzed = frame.capturedAt;
    final pitch = pitchDetector.detect(frame.samples, frame.sampleRate);
    final update = _tracker.observe(pitch, frame.capturedAt);
    _last = RealtimeDetection(
      source: RealtimeDetectorSource.yin,
      events: update.events,
      activeNotes: Set<int>.unmodifiable(
        update.stableNote == null ? <int>{} : <int>{update.stableNote!},
      ),
      evidence: RealtimeEvidence.periodicity,
      candidateMidiNote: pitch?.midiNote,
      periodicityConfidence: pitch?.confidence,
    );
    return _last;
  }

  @override
  void reset() {
    _tracker.reset();
    _lastAnalyzed = null;
    _last = const RealtimeDetection(
      source: RealtimeDetectorSource.yin,
      events: <NoteEvent>[],
      activeNotes: <int>{},
      evidence: RealtimeEvidence.periodicity,
    );
  }
}

/// Wraps the existing FFT + heuristic chord tracker, without claiming that
/// FFT magnitudes are model probabilities or providing invented confidence.
class FftRealtimeDetector implements RealtimeNoteDetector {
  FftRealtimeDetector({PolyphonicNoteTracker? tracker})
    : _tracker = tracker ?? PolyphonicNoteTracker();

  final PolyphonicNoteTracker _tracker;

  @override
  RealtimeDetection observe(PcmFrame frame) {
    return RealtimeDetection(
      source: RealtimeDetectorSource.legacyPolyphonicFft,
      events: _tracker.observe(
        frame.samples,
        frame.sampleRate,
        frame.capturedAt,
      ),
      activeNotes: _tracker.activeNotes,
      evidence: RealtimeEvidence.uncalibratedPolyphony,
    );
  }

  @override
  void reset() => _tracker.reset();
}
