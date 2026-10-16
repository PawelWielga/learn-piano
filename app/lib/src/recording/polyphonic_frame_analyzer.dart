import 'dart:math' as math;
import 'dart:typed_data';

/// Spectral multi-pitch candidates for decoded files and buffered live PCM.
///
/// A small, dependency-free harmonic matching pursuit. This is deliberately a
/// lightweight approximation to piano transcription, not an ML piano model:
/// ambiguous overlapping partials and reverb can still create false notes.
class PolyphonicFrameAnalyzer {
  PolyphonicFrameAnalyzer(
    int sourceSampleRate, {
    this.minMidi = 36,
    this.maxMidi = 96,
    this.maxVoices = 8,
    this.sensitivity = 0.17,
  }) : assert(sourceSampleRate > 0),
       assert(minMidi >= 0 && maxMidi <= 127 && minMidi < maxMidi),
       assert(maxVoices > 0),
       decimation = sourceSampleRate >= 32000 ? 2 : 1,
       sampleRate = sourceSampleRate / (sourceSampleRate >= 32000 ? 2 : 1) {
    for (var i = 0; i < fftSize; i++) {
      _window[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / (fftSize - 1));
      var x = i;
      var reversed = 0;
      for (var bit = 0; bit < 12; bit++) {
        reversed = (reversed << 1) | (x & 1);
        x >>= 1;
      }
      _bitReverse[i] = reversed;
    }
    for (var i = 0; i < fftSize ~/ 2; i++) {
      _cos[i] = math.cos(-2 * math.pi * i / fftSize);
      _sin[i] = math.sin(-2 * math.pi * i / fftSize);
    }
    _partials = List.generate(maxMidi - minMidi + 1, (index) {
      final frequency = 440 * math.pow(2, (index + minMidi - 69) / 12);
      return List<double>.generate(
        6,
        (harmonic) => frequency * (harmonic + 1) * fftSize / sampleRate,
      );
    });
  }

  static const fftSize = 4096;
  static const _weights = <double>[1, 0.65, 0.46, 0.32, 0.24, 0.18];

  final int minMidi;
  final int maxMidi;
  final int maxVoices;
  final double sensitivity;
  final int decimation;
  final double sampleRate;

  final _window = Float64List(fftSize);
  final _real = Float64List(fftSize);
  final _imag = Float64List(fftSize);
  final _magnitude = Float64List(fftSize ~/ 2 + 1);
  final _residual = Float64List(fftSize ~/ 2 + 1);
  final _cos = Float64List(fftSize ~/ 2);
  final _sin = Float64List(fftSize ~/ 2);
  final _bitReverse = Uint16List(fftSize);
  late final List<List<double>> _partials;

  /// [pcm] must already be at [sampleRate], not at the original source rate.
  /// For sources >=32 kHz, filter and downsample using AntiAliasDecimator
  /// before passing a center index divided by [decimation].
  ///
  /// The returned strengths are in PCM-like linear amplitude units. A pitch
  /// can be present alongside others; returned data is owned by the caller.
  Float64List analyze(Float32List pcm, int centerSample) {
    for (var i = 0; i < fftSize; i++) {
      // Input has already been low-pass filtered and decimated once when
      // applicable. Never stride over raw high-rate PCM here.
      final source = centerSample + i - fftSize ~/ 2;
      final sample = source < 0 || source >= pcm.length ? 0.0 : pcm[source];
      _real[_bitReverse[i]] = sample * _window[i];
      _imag[i] = 0;
    }

    // In-place radix-2 FFT with cached twiddle factors and bit reversal.
    for (var length = 2; length <= fftSize; length <<= 1) {
      final half = length ~/ 2;
      final stride = fftSize ~/ length;
      for (var base = 0; base < fftSize; base += length) {
        for (var j = 0; j < half; j++) {
          final low = base + j;
          final high = low + half;
          final c = _cos[j * stride];
          final s = _sin[j * stride];
          final real = _real[high] * c - _imag[high] * s;
          final imag = _real[high] * s + _imag[high] * c;
          _real[high] = _real[low] - real;
          _imag[high] = _imag[low] - imag;
          _real[low] += real;
          _imag[low] += imag;
        }
      }
    }

    var globalPeak = 0.0;
    for (var i = 1; i < _magnitude.length; i++) {
      final value = math.sqrt(_real[i] * _real[i] + _imag[i] * _imag[i]);
      _magnitude[i] = value;
    }
    // Suppress broadband energy without flattening actual narrow peaks.
    for (var i = 3; i < _magnitude.length - 3; i++) {
      final value = math.max(
        0.0,
        _magnitude[i] - 0.18 * (_magnitude[i - 3] + _magnitude[i + 3]),
      );
      _residual[i] = value;
      if (i * sampleRate / fftSize >= 60 &&
          i * sampleRate / fftSize <= 2000 &&
          value > globalPeak) {
        globalPeak = value;
      }
    }
    _residual.fillRange(0, 3, 0);
    _residual.fillRange(_residual.length - 3, _residual.length, 0);

    final strengths = Float64List(maxMidi - minMidi + 1);
    if (globalPeak < 1e-7) return strengths;

    final chosen = <int>{};
    for (var voice = 0; voice < maxVoices; voice++) {
      var best = -1;
      var bestScore = 0.0;
      var bestFundamental = 0.0;
      for (var note = 0; note < strengths.length; note++) {
        if (chosen.contains(note)) continue;
        final bins = _partials[note];
        final fundamental = _peakAt(bins[0]);
        if (fundamental < globalPeak * sensitivity) continue;
        var score = fundamental;
        for (var harmonic = 1; harmonic < bins.length; harmonic++) {
          score += _weights[harmonic] * _peakAt(bins[harmonic]);
        }
        // Favor an actual fundamental over the loud overtones of lower keys.
        score += 0.35 * fundamental;
        if (score > bestScore) {
          bestScore = score;
          bestFundamental = fundamental;
          best = note;
        }
      }
      if (best < 0) break;
      chosen.add(best);
      strengths[best] = bestFundamental / (fftSize / 4);

      // Subtract the selected pitch's partials, *not* all energy at the
      // harmonics: an independently played high note can share a bass partial.
      final bins = _partials[best];
      for (var harmonic = 0; harmonic < bins.length; harmonic++) {
        final predicted =
            bestFundamental * (harmonic == 0 ? 1.25 : _weights[harmonic]);
        final center = bins[harmonic].round();
        for (var offset = -2; offset <= 2; offset++) {
          final index = center + offset;
          if (index < 1 || index >= _residual.length - 1) continue;
          final fraction = offset.abs() <= 1 ? 1.0 : 0.42;
          _residual[index] = math.max(
            0.0,
            _residual[index] - predicted * fraction,
          );
        }
      }
    }
    return strengths;
  }

  double _peakAt(double bin) {
    if (bin < 2 || bin >= _residual.length - 2) return 0;
    final middle = bin.round();
    final closeness = (bin - middle).abs();
    final near = math.max(_residual[middle - 1], _residual[middle + 1]);
    return math.max(_residual[middle], near * (0.85 - 0.2 * closeness));
  }
}
