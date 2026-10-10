import 'dart:math' as math;
import 'dart:typed_data';

/// One FFT frequency bin, scaled relative to the loudest bin in the window.
class SpectrumPoint {
  const SpectrumPoint(this.frequencyHz, this.level);

  final double frequencyHz;
  final double level;
}

/// A local maximum in the spectrum. A peak can be a harmonic, not a key press.
class SpectrumPeak {
  const SpectrumPeak(this.frequencyHz, this.level);

  final double frequencyHz;
  final double level;
}

class SpectrumSnapshot {
  const SpectrumSnapshot(this.points, this.peaks);

  final List<SpectrumPoint> points;
  final List<SpectrumPeak> peaks;

  static const empty = SpectrumSnapshot([], []);
}

/// Diagnostic FFT of a rolling microphone window. Independent of pitch
/// detection: the strongest harmonic is not necessarily the played note.
///
/// An 8192-sample Hann window resolves bins about 5.9 Hz apart at 48 kHz,
/// including low C2. Frames are accumulated continuously but the FFT itself
/// should be called only at a throttled UI cadence and when debug is visible.
class SpectrumAnalyzer {
  SpectrumAnalyzer();

  static const int windowSize = 8192;
  static const double minFrequencyHz = 60;
  static const double maxFrequencyHz = 1200;
  static const double _noiseFloorDb = -55;

  final Float32List _samples = Float32List(windowSize);
  int _write = 0;
  int _filled = 0;

  void addSamples(Float32List samples) {
    for (final value in samples) {
      _samples[_write] = value.isFinite ? value : 0;
      _write = (_write + 1) % windowSize;
      if (_filled < windowSize) _filled++;
    }
  }

  void reset() {
    _write = 0;
    _filled = 0;
  }

  /// Null until a full window has arrived or when sample rate is invalid.
  /// Silence returns an empty snapshot so the view clears stale peaks.
  SpectrumSnapshot? analyze(int sampleRate) {
    if (sampleRate <= 0 || _filled < windowSize) return null;

    final real = Float64List(windowSize);
    final imaginary = Float64List(windowSize);
    var energy = 0.0;
    for (var i = 0; i < windowSize; i++) {
      final sample = _samples[(_write + i) % windowSize];
      energy += sample * sample;
      final window = 0.5 -
          0.5 * math.cos(2 * math.pi * i / (windowSize - 1));
      real[i] = sample * window;
    }
    if (math.sqrt(energy / windowSize) < 0.006) {
      return SpectrumSnapshot.empty;
    }

    _fft(real, imaginary);
    final minBin = math.max(
      1,
      (minFrequencyHz * windowSize / sampleRate).ceil(),
    );
    final maxBin = math.min(
      windowSize ~/ 2 - 1,
      (maxFrequencyHz * windowSize / sampleRate).floor(),
    );
    if (maxBin <= minBin + 2) return SpectrumSnapshot.empty;

    final magnitudes = Float64List(maxBin + 2);
    var strongest = 0.0;
    for (var bin = minBin - 1; bin <= maxBin + 1; bin++) {
      final amplitude = math.sqrt(
        real[bin] * real[bin] + imaginary[bin] * imaginary[bin],
      );
      magnitudes[bin] = amplitude;
      if (bin >= minBin && bin <= maxBin) {
        strongest = math.max(strongest, amplitude);
      }
    }
    if (strongest <= 0) return SpectrumSnapshot.empty;

    double levelFor(double magnitude) {
      final db = 20 * math.log(math.max(magnitude / strongest, 1e-12)) /
          math.ln10;
      return ((db - _noiseFloorDb) / -_noiseFloorDb)
          .clamp(0.0, 1.0)
          .toDouble();
    }

    final points = <SpectrumPoint>[];
    final peaks = <SpectrumPeak>[];
    for (var bin = minBin; bin <= maxBin; bin++) {
      final level = levelFor(magnitudes[bin]);
      final frequency = bin * sampleRate / windowSize;
      points.add(SpectrumPoint(frequency, level));

      if (level < 0.38 ||
          magnitudes[bin] <= magnitudes[bin - 1] ||
          magnitudes[bin] < magnitudes[bin + 1]) {
        continue;
      }

      // Parabolic interpolation in log magnitude places the displayed peak
      // between FFT bins. This is a visualization, not a pitch estimator.
      final left = math.log(math.max(magnitudes[bin - 1], 1e-12));
      final center = math.log(math.max(magnitudes[bin], 1e-12));
      final right = math.log(math.max(magnitudes[bin + 1], 1e-12));
      final divisor = left - 2 * center + right;
      var offset = 0.0;
      if (divisor.abs() > 1e-12) {
        offset = (0.5 * (left - right) / divisor).clamp(-1.0, 1.0);
      }
      peaks.add(
        SpectrumPeak((bin + offset) * sampleRate / windowSize, level),
      );
    }

    // Keep the strongest peaks, but present them from low to high pitch.
    peaks.sort((a, b) => b.level.compareTo(a.level));
    final strongestPeaks = peaks.take(8).toList()
      ..sort((a, b) => a.frequencyHz.compareTo(b.frequencyHz));
    return SpectrumSnapshot(points, strongestPeaks);
  }

  /// Iterative radix-2 Cooley-Tukey FFT. Window size is fixed and a power of 2.
  static void _fft(Float64List real, Float64List imaginary) {
    final count = real.length;
    for (var i = 1, j = 0; i < count; i++) {
      var bit = count >> 1;
      while ((j & bit) != 0) {
        j ^= bit;
        bit >>= 1;
      }
      j ^= bit;
      if (i < j) {
        final r = real[i];
        real[i] = real[j];
        real[j] = r;
        final im = imaginary[i];
        imaginary[i] = imaginary[j];
        imaginary[j] = im;
      }
    }

    for (var size = 2; size <= count; size <<= 1) {
      final angle = -2 * math.pi / size;
      final cosine = math.cos(angle);
      final sine = math.sin(angle);
      for (var start = 0; start < count; start += size) {
        var wr = 1.0;
        var wi = 0.0;
        for (var j = 0; j < size ~/ 2; j++) {
          final even = start + j;
          final odd = even + size ~/ 2;
          final tr = wr * real[odd] - wi * imaginary[odd];
          final ti = wr * imaginary[odd] + wi * real[odd];

          real[odd] = real[even] - tr;
          imaginary[odd] = imaginary[even] - ti;
          real[even] += tr;
          imaginary[even] += ti;

          final nextWr = wr * cosine - wi * sine;
          wi = wr * sine + wi * cosine;
          wr = nextWr;
        }
      }
    }
  }
}
