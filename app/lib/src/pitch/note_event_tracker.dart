import 'pitch_detector.dart';

/// A confirmed key onset or an acoustically inferred release.
///
/// A release is not a MIDI key-up measurement: a piano may keep ringing.
enum NoteEventType { noteOn, noteOff }

class NoteEvent {
  const NoteEvent({
    required this.type,
    required this.midiNote,
    required this.at,
  });

  final NoteEventType type;
  final int midiNote;
  final Duration at;
}

enum NoteDetectionPhase { silent, candidate, stable, releasing }

class NoteDetectionUpdate {
  const NoteDetectionUpdate({
    required this.phase,
    required this.stableNote,
    required this.candidateNote,
    required this.events,
  });

  final NoteDetectionPhase phase;
  final int? stableNote;
  final int? candidateNote;
  final List<NoteEvent> events;
}

/// Converts successive YIN pitch estimates into distinct NoteOn/NoteOff events.
///
/// One stable pitch causes at most one NoteOn until a sufficiently long silence
/// (or a sufficiently stable different pitch) has been observed. In particular,
/// an unchanged ringing tone cannot trigger a second NoteOn. Re-strikes of the
/// same pitch without an audible gap are intentionally NOT guessed from volume.
class NoteEventTracker {
  NoteEventTracker({
    this.minStableDuration = const Duration(milliseconds: 200),
    this.minReleaseDuration = const Duration(milliseconds: 240),
    this.maxObservationGap = const Duration(milliseconds: 400),
    this.minConfidence = 0.93,
    this.maxCentsDeviation = 35,
  }) : assert(!minStableDuration.isNegative),
       assert(!minReleaseDuration.isNegative),
       assert(!maxObservationGap.isNegative),
       assert(minConfidence >= 0 && minConfidence <= 1),
       assert(maxCentsDeviation >= 0 && maxCentsDeviation <= 50);

  final Duration minStableDuration;
  final Duration minReleaseDuration;

  /// Interruptions larger than this restart pending candidates, not held notes.
  final Duration maxObservationGap;
  final double minConfidence;
  final double maxCentsDeviation;

  int? _stableNote;
  int? _candidateNote;
  Duration? _candidateSince;
  Duration? _releaseSince;
  Duration? _lastObservationAt;

  int? get stableNote => _stableNote;
  int? get candidateNote => _candidateNote;

  NoteDetectionPhase get phase {
    if (_candidateNote != null) return NoteDetectionPhase.candidate;
    if (_releaseSince != null) return NoteDetectionPhase.releasing;
    if (_stableNote != null) return NoteDetectionPhase.stable;
    return NoteDetectionPhase.silent;
  }

  /// Feed only frames analyzed by the pitch detector, in AudioContext order.
  ///
  /// Timestamps are monotonic durations within one audio session. Call
  /// [reset] when the microphone stops or is interrupted.
  NoteDetectionUpdate observe(PitchEstimate? estimate, Duration at) {
    final events = <NoteEvent>[];
    final previous = _lastObservationAt;
    if (previous != null && at <= previous) return _snapshot(events);

    if (previous != null && at - previous > maxObservationGap) {
      // A paused/throttled analysis cannot be evidence of uninterrupted
      // stability or a continuous period of silence.
      _candidateNote = null;
      _candidateSince = null;
      _releaseSince = null;
    }
    _lastObservationAt = at;

    final note =
        estimate != null &&
            estimate.confidence >= minConfidence &&
            estimate.centsFromNote.isFinite &&
            estimate.centsFromNote.abs() <= maxCentsDeviation &&
            estimate.midiNote >= 0 &&
            estimate.midiNote <= 127
        ? estimate.midiNote
        : null;

    if (note == null) {
      _candidateNote = null;
      _candidateSince = null;
      if (_stableNote != null) {
        _releaseSince ??= at;
        if (at - _releaseSince! >= minReleaseDuration) {
          events.add(
            NoteEvent(
              type: NoteEventType.noteOff,
              midiNote: _stableNote!,
              at: at,
            ),
          );
          _stableNote = null;
          _releaseSince = null;
        }
      }
    } else {
      _releaseSince = null;
      if (note == _stableNote) {
        _candidateNote = null;
        _candidateSince = null;
      } else {
        if (note != _candidateNote) {
          _candidateNote = note;
          _candidateSince = at;
        } else if (at - _candidateSince! >= minStableDuration) {
          if (_stableNote case final oldNote?) {
            events.add(
              NoteEvent(type: NoteEventType.noteOff, midiNote: oldNote, at: at),
            );
          }
          _stableNote = note;
          events.add(
            NoteEvent(type: NoteEventType.noteOn, midiNote: note, at: at),
          );
          _candidateNote = null;
          _candidateSince = null;
        }
      }
    }

    return _snapshot(events);
  }

  void reset() {
    _stableNote = null;
    _candidateNote = null;
    _candidateSince = null;
    _releaseSince = null;
    _lastObservationAt = null;
  }

  NoteDetectionUpdate _snapshot(List<NoteEvent> events) => NoteDetectionUpdate(
    phase: phase,
    stableNote: _stableNote,
    candidateNote: _candidateNote,
    events: List.unmodifiable(events),
  );
}
