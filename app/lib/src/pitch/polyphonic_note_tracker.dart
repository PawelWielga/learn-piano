import 'dart:math' as math;
import 'dart:typed_data';

import '../recording/polyphonic_frame_analyzer.dart';
import 'note_event_tracker.dart';

/// Experimental multi-pitch microphone tracker for chord exercises.
///
/// Buffers consecutive 2048-sample AudioWorklet packets before FFT. Pitch
/// events are stable onsets, not a perfect measure of physical key state;
/// piano resonance and shared harmonics can still produce false candidates.
class PolyphonicNoteTracker {
  PolyphonicNoteTracker({this.minimumRms = 0.015});

  final double minimumRms;
  static const _release = Duration(milliseconds: 240);
  static const _attack = Duration(milliseconds: 120);
  static const _gap = Duration(milliseconds: 450);
  static const _floor = 0.012;

  PolyphonicFrameAnalyzer? _analyzer;
  int? _sampleRate;
  final Float32List _buffer = Float32List(8192);
  int _received = 0;
  int _samplesSinceAnalysis = 0;
  Duration? _lastAt;
  final Map<int, _PitchState> _states = <int, _PitchState>{};

  Set<int> get activeNotes => Set<int>.unmodifiable(
    _states.entries
        .where((entry) => entry.value.active)
        .map((entry) => entry.key),
  );

  /// Returns note-on/off transitions; empty frames do not imply silence.
  List<NoteEvent> observe(Float32List samples, int sampleRate, Duration at) {
    if (samples.isEmpty || sampleRate < 8000 || sampleRate > 96000) {
      return const [];
    }
    if (_sampleRate != sampleRate ||
        (_lastAt != null && (at <= _lastAt! || at - _lastAt! > _gap))) {
      reset();
    }
    _sampleRate = sampleRate;
    _lastAt = at;
    _analyzer ??= PolyphonicFrameAnalyzer(
      sampleRate,
      minMidi: 36,
      maxMidi: 96,
      maxVoices: 6,
      sensitivity: 0.23,
    );

    // Keep the newest 8192 samples; avoid FFT on half-empty worklet packets.
    final count = math.min(samples.length, _buffer.length);
    if (count == _buffer.length) {
      _buffer.setRange(0, count, samples, samples.length - count);
    } else {
      _buffer.setRange(0, _buffer.length - count, _buffer, count);
      _buffer.setRange(
        _buffer.length - count,
        _buffer.length,
        samples,
        samples.length - count,
      );
    }
    _received = math.min(_buffer.length, _received + count);
    _samplesSinceAnalysis += count;
    if (_received < _buffer.length) return const [];
    // Keep all incoming PCM, but run the spectral matcher about 12 times/s.
    if (_samplesSinceAnalysis < sampleRate ~/ 12) return const [];
    _samplesSinceAnalysis = 0;

    var sum = 0.0;
    // Gate based on the newest 2048 samples, not long decaying FFT tails.
    for (var i = _buffer.length - 2048; i < _buffer.length; i++) {
      sum += _buffer[i] * _buffer[i];
    }
    final quiet = math.sqrt(sum / 2048) < minimumRms;
    final levels = quiet
        ? Float64List(_analyzer!.maxMidi - _analyzer!.minMidi + 1)
        : _analyzer!.analyze(_buffer, _buffer.length ~/ 2);
    final events = <NoteEvent>[];

    for (var i = 0; i < levels.length; i++) {
      final note = _analyzer!.minMidi + i;
      final state = _states.putIfAbsent(note, _PitchState.new);
      if (!quiet && levels[i] >= _floor) {
        state.missingSince = null;
        state.presentSince ??= at;
        if (!state.active && at - state.presentSince! >= _attack) {
          state.active = true;
          events.add(
            NoteEvent(type: NoteEventType.noteOn, midiNote: note, at: at),
          );
        }
      } else {
        state.presentSince = null;
        if (state.active) {
          state.missingSince ??= at;
          if (at - state.missingSince! >= _release) {
            state.active = false;
            state.missingSince = null;
            events.add(
              NoteEvent(type: NoteEventType.noteOff, midiNote: note, at: at),
            );
          }
        }
      }
    }
    return events;
  }

  void reset() {
    _analyzer = null;
    _sampleRate = null;
    _received = 0;
    _samplesSinceAnalysis = 0;
    _lastAt = null;
    _buffer.fillRange(0, _buffer.length, 0);
    _states.clear();
  }
}

class _PitchState {
  Duration? presentSince;
  Duration? missingSince;
  bool active = false;
}
