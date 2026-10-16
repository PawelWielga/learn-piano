import 'dart:math' as math;
import 'dart:typed_data';

/// Half-band, linear-phase FIR decimator for decoded file audio.
///
/// When reducing 44.1/48 kHz PCM by two, selecting every second sample would
/// fold frequencies above the new Nyquist limit into false lower frequencies.
/// The 63-tap Hamming-windowed sinc attenuates those frequencies before
/// downsampling. Only the center and odd offsets are non-zero.
class AntiAliasDecimator {
  const AntiAliasDecimator._();

  static const _radius = 31;
  static final Float64List _kernel = _buildKernel();

  static Float64List _buildKernel() {
    const cutoff = 0.25; // Cycles per original sample: half the new Nyquist.
    final weights = Float64List(_radius * 2 + 1);
    var total = 0.0;
    for (var offset = -_radius; offset <= _radius; offset++) {
      // The ideal half-band sinc has zero taps at every nonzero even offset.
      if (offset != 0 && offset.isEven) continue;
      final sinc = offset == 0
          ? 2 * cutoff
          : math.sin(2 * math.pi * cutoff * offset) / (math.pi * offset);
      final window = 0.54 + 0.46 * math.cos(math.pi * offset / _radius);
      final weight = sinc * window;
      weights[offset + _radius] = weight;
      total += weight;
    }
    for (var i = 0; i < weights.length; i++) {
      weights[i] /= total; // Preserve DC / low-frequency amplitude.
    }
    return weights;
  }

  static int outputLength(int inputLength) => (inputLength + 1) ~/ 2;

  /// Write a disjoint range of output samples. Chunking allows the caller to
  /// yield to Flutter and check cancellation during long imports.
  ///
  /// The symmetric kernel is centered on original sample 2*i, so the output
  /// stays aligned with the source timeline (no artificial onset delay).
  static void processRange(
    Float32List input,
    Float32List output,
    int from,
    int to,
  ) {
    if (output.length != outputLength(input.length) ||
        from < 0 ||
        from > to ||
        to > output.length) {
      throw RangeError('Invalid decimator output buffer or range.');
    }
    final kernel = _kernel;
    for (var i = from; i < to; i++) {
      final center = i * 2;
      var sample = input[center] * kernel[_radius];
      for (var offset = -_radius; offset <= _radius; offset += 2) {
        final sourceIndex = center + offset;
        if (sourceIndex >= 0 && sourceIndex < input.length) {
          sample += input[sourceIndex] * kernel[offset + _radius];
        }
      }
      output[i] = sample;
    }
  }

  static Float32List decimate(Float32List input) {
    final output = Float32List(outputLength(input.length));
    processRange(input, output, 0, output.length);
    return output;
  }
}
