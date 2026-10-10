import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:learn_piano/src/audio/spectrum_analyzer.dart';

void addTone(
  SpectrumAnalyzer analyzer,
  double fundamental, {
  int sampleRate = 48000,
  double secondHarmonic = 0,
}) {
  final samples = Float32List.fromList(
    List<double>.generate(SpectrumAnalyzer.windowSize, (i) {
      final phase = 2 * math.pi * fundamental * i / sampleRate;
      return 0.35 * math.sin(phase) +
          secondHarmonic * math.sin(2 * phase);
    }),
  );
  for (var i = 0; i < samples.length; i += 2048) {
    analyzer.addSamples(Float32List.sublistView(samples, i, i + 2048));
  }
}

void main() {
  test('waits for a full window and resets without retaining stale data', () {
    final analyzer = SpectrumAnalyzer();
    expect(analyzer.analyze(48000), isNull);
    analyzer.addSamples(Float32List(2048));
    expect(analyzer.analyze(48000), isNull);
    analyzer.reset();

    addTone(analyzer, 440);
    expect(analyzer.analyze(0), isNull);
    expect(analyzer.analyze(48000)?.peaks, isNotEmpty);
    analyzer.reset();
    expect(analyzer.analyze(48000), isNull);
    analyzer.addSamples(Float32List(SpectrumAnalyzer.windowSize));
    expect(analyzer.analyze(48000)?.peaks, isEmpty);
  });

  test('locates low C2 and A4 with the actual 44.1/48 kHz sample rate', () {
    for (final sampleRate in [44100, 48000]) {
      for (final frequency in [65.4064, 440.0]) {
        final analyzer = SpectrumAnalyzer();
        addTone(analyzer, frequency, sampleRate: sampleRate);
        final spectrum = analyzer.analyze(sampleRate)!;
        expect(spectrum.points, isNotEmpty);
        expect(spectrum.peaks, isNotEmpty);
        expect(
          spectrum.peaks.any(
            (peak) => (peak.frequencyHz - frequency).abs() < 6,
          ),
          isTrue,
          reason: '$frequency Hz, sampleRate $sampleRate',
        );
      }
    }
  });

  test('shows separate fundamental and harmonic peaks', () {
    final analyzer = SpectrumAnalyzer();
    addTone(analyzer, 220, secondHarmonic: 0.6);
    final peaks = analyzer.analyze(48000)!.peaks;
    expect(peaks.any((peak) => (peak.frequencyHz - 220).abs() < 5), isTrue);
    expect(peaks.any((peak) => (peak.frequencyHz - 440).abs() < 5), isTrue);
  });

  test('handles non-finite samples without contaminating later frames', () {
    final analyzer = SpectrumAnalyzer();
    analyzer.addSamples(
      Float32List.fromList([double.nan, double.infinity]),
    );
    addTone(analyzer, 440);
    final peaks = analyzer.analyze(48000)!.peaks;
    expect(peaks.any((peak) => (peak.frequencyHz - 440).abs() < 5), isTrue);
  });
}
