import 'dart:math' as math;
import 'dart:typed_data';

/// A single unfiltered pitch candidate. This is NOT a NoteOn event.
/// Use NoteEventTracker to obtain stable key-on/key-off events.
class PitchEstimate {
  const PitchEstimate({
    required this.frequencyHz,
    required this.midiNote,
    required this.confidence,
    required this.centsFromNote,
  });

  final double frequencyHz;
  final int midiNote;
  final double confidence;
  final double centsFromNote;

  static const _noteNames = [
    'C',
    'C#',
    'D',
    'D#',
    'E',
    'F',
    'F#',
    'G',
    'G#',
    'A',
    'A#',
    'B',
  ];

  /// Scientific pitch notation: MIDI 60 = C4; MIDI 69 = A4.
  String get noteName => nameForMidi(midiNote);

  static String nameForMidi(int note) =>
      '${_noteNames[note % 12]}${note ~/ 12 - 1}';
}

/// YIN cumulative mean normalized difference (CMNDF) pitch estimator.
///
/// The detector takes one mono PCM frame and does not depend on Flutter,
/// microphone APIs or previous frames. Null means silence, invalid input,
/// unsupported range or no sufficiently periodic candidate.
class PitchDetector {
  const PitchDetector({
    // C2 (65.4 Hz) must be playable; include detuning margin.
    this.minFrequencyHz = 60,
    this.maxFrequencyHz = 1500,
    this.minRms = 0.015,
    this.yinThreshold = 0.18,
    this.minConfidence = 0.94,
  }) : assert(minFrequencyHz > 0),
       assert(maxFrequencyHz > minFrequencyHz),
       assert(minRms > 0),
       assert(yinThreshold > 0 && yinThreshold < 1),
       assert(minConfidence > 0 && minConfidence < 1);

  final double minFrequencyHz;
  final double maxFrequencyHz;
  final double minRms;
  final double yinThreshold;
  final double minConfidence;

  PitchEstimate? detect(Float32List samples, int sampleRate) {
    if (sampleRate <= 0 || samples.length < 1024) return null;

    final maxLag = (sampleRate / minFrequencyHz).ceil();
    final minLag = math.max(2, (sampleRate / maxFrequencyHz).floor());

    // Need enough independent samples for a period comparison.
    if (maxLag >= samples.length ~/ 2 || minLag >= maxLag) return null;

    var energy = 0.0;
    for (final sample in samples) {
      if (!sample.isFinite) return null;
      energy += sample * sample;
    }
    final rms = math.sqrt(energy / samples.length);
    if (rms < minRms) return null;

    // Use the same comparison window for every lag to avoid favoring
    // large lags due to a shorter overlap.
    final comparisonSize = samples.length - maxLag;
    final cmndf = Float64List(maxLag + 1);
    var cumulativeDifference = 0.0;

    for (var lag = 1; lag <= maxLag; lag++) {
      var squaredDifference = 0.0;
      for (var i = 0; i < comparisonSize; i++) {
        final delta = samples[i] - samples[i + lag];
        squaredDifference += delta * delta;
      }
      cumulativeDifference += squaredDifference;
      cmndf[lag] = cumulativeDifference <= 0
          ? 1
          : (lag * squaredDifference) / cumulativeDifference;
    }

    // YIN picks the first strong periodicity dip, not the lowest
    // difference overall (which frequently gives an octave error).
    int? selectedLag;
    for (var lag = minLag; lag <= maxLag; lag++) {
      if (cmndf[lag] >= yinThreshold) continue;
      while (lag + 1 <= maxLag && cmndf[lag + 1] < cmndf[lag]) {
        lag++;
      }
      selectedLag = lag;
      break;
    }

    // At the search boundary, a still-decreasing difference can mimic a
    // periodicity below minFrequencyHz. Require an actual interior minimum.
    if (selectedLag == null || selectedLag == maxLag) return null;
    final confidence = (1.0 - cmndf[selectedLag]).clamp(0.0, 1.0);
    if (confidence < minConfidence) return null;

    // Quadratic interpolation improves accuracy between integer lags,
    // especially at high pitches where periods contain few samples.
    var refinedLag = selectedLag.toDouble();
    if (selectedLag > 1 && selectedLag < maxLag) {
      final left = cmndf[selectedLag - 1];
      final middle = cmndf[selectedLag];
      final right = cmndf[selectedLag + 1];
      final denominator = left - 2 * middle + right;
      if (denominator.abs() > 1e-12) {
        final offset = (left - right) / (2 * denominator);
        if (offset.isFinite && offset.abs() <= 1) {
          refinedLag += offset;
        }
      }
    }

    final frequencyHz = sampleRate / refinedLag;
    if (!frequencyHz.isFinite ||
        frequencyHz < minFrequencyHz ||
        frequencyHz > maxFrequencyHz) {
      return null;
    }

    final fractionalMidi = 69 + 12 * math.log(frequencyHz / 440) / math.ln2;
    final midiNote = fractionalMidi.round();
    if (midiNote < 0 || midiNote > 127) return null;

    return PitchEstimate(
      frequencyHz: frequencyHz,
      midiNote: midiNote,
      confidence: confidence,
      centsFromNote: (fractionalMidi - midiNote) * 100,
    );
  }
}
